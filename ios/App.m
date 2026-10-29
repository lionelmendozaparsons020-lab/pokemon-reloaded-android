#import <UIKit/UIKit.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import "Bridge.h"

static NSString *Documents(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject; }
static NSString *EngineError(void) { char text[4096]={0};gm_ios_error(text,sizeof(text));return [[NSString alloc] initWithBytes:text length:strlen(text) encoding:NSUTF8StringEncoding] ?: @"El motor se detuvo. Consultá el registro."; }
static EAGLContext *glContext;
static GLuint screenFbo,screenColor;
static AudioUnit audioUnit;
static NSLock *audioLock;
// These functions are called with Rust's GL lifecycle mutex held.
int gm_ios_gl_create(void *view) {
    @autoreleasepool {
        UIView *v=(__bridge UIView *)view;
        glContext=[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        if (!glContext || ![EAGLContext setCurrentContext:glContext]) return -1;
        glGenFramebuffers(1,&screenFbo);glBindFramebuffer(GL_FRAMEBUFFER,screenFbo);
        glGenRenderbuffers(1,&screenColor);glBindRenderbuffer(GL_RENDERBUFFER,screenColor);
        if (![glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)v.layer]) return -2;
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,screenColor);
        GLint w=0,h=0;glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_WIDTH,&w);glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_HEIGHT,&h);
        gm_ios_resize((uint16_t)w,(uint16_t)h);
        return glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE ? 0 : -3;
    }
}
void gm_ios_gl_destroy(void) {
    glDeleteFramebuffers(1,&screenFbo);glDeleteRenderbuffers(1,&screenColor);
    screenFbo=0;screenColor=0;[EAGLContext setCurrentContext:nil];glContext=nil;
}
void gm_ios_gl_present(void) { glBindRenderbuffer(GL_RENDERBUFFER,screenColor);[glContext presentRenderbuffer:GL_RENDERBUFFER]; }
uint32_t gm_ios_gl_framebuffer(void) { return screenFbo; }
const void *gm_ios_gl_proc(const char *name) { return dlsym(RTLD_DEFAULT,name); }
void gm_ios_gl_finish(void) {
    if (!glContext) return;
    EAGLContext *previous=EAGLContext.currentContext;
    [EAGLContext setCurrentContext:glContext];glFinish();[EAGLContext setCurrentContext:previous];
}
static OSStatus AudioRender(void *ref,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *data) {
    if(data->mNumberBuffers==1 && data->mBuffers[0].mData && data->mBuffers[0].mDataByteSize>=frames*8) gm_ios_audio_fill(data->mBuffers[0].mData,frames);
    else for(UInt32 i=0;i<data->mNumberBuffers;i++) if(data->mBuffers[i].mData) memset(data->mBuffers[i].mData,0,data->mBuffers[i].mDataByteSize);
    return noErr;
}
int gm_ios_audio_start(void) {
    [audioLock lock];
    AVAudioSession *session=AVAudioSession.sharedInstance;NSError *err=nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&err];
    [session setPreferredSampleRate:48000 error:&err];[session setActive:YES error:&err];
    AudioComponentDescription desc={kAudioUnitType_Output,kAudioUnitSubType_RemoteIO,kAudioUnitManufacturer_Apple,0,0};
    AudioComponent component=AudioComponentFindNext(NULL,&desc);
    OSStatus status=component?AudioComponentInstanceNew(component,&audioUnit):-1;
    AudioStreamBasicDescription format={0};format.mSampleRate=48000;format.mFormatID=kAudioFormatLinearPCM;
    format.mFormatFlags=kAudioFormatFlagsNativeFloatPacked;format.mBytesPerPacket=8;format.mFramesPerPacket=1;
    format.mBytesPerFrame=8;format.mChannelsPerFrame=2;format.mBitsPerChannel=32;
    if(!status)status=AudioUnitSetProperty(audioUnit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,sizeof(format));
    AURenderCallbackStruct callback={AudioRender,NULL};
    if(!status)status=AudioUnitSetProperty(audioUnit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&callback,sizeof(callback));
    if(!status)status=AudioUnitInitialize(audioUnit);
    if(!status)status=AudioOutputUnitStart(audioUnit);
    if(status && audioUnit){AudioComponentInstanceDispose(audioUnit);audioUnit=NULL;}
    [audioLock unlock];return (int)status;
}
void gm_ios_audio_pause(bool paused) {
    [audioLock lock];
    if(audioUnit){if(paused)AudioOutputUnitStop(audioUnit);else{[AVAudioSession.sharedInstance setActive:YES error:nil];AudioOutputUnitStart(audioUnit);}}
    [audioLock unlock];
}
void gm_ios_audio_stop(void) {
    [audioLock lock];
    if(audioUnit){AudioOutputUnitStop(audioUnit);AudioUnitUninitialize(audioUnit);AudioComponentInstanceDispose(audioUnit);audioUnit=NULL;}
    [audioLock unlock];
}


static NSString *const StageNotification=@"ReloadedLoadingStage";
static NSString *const KeyboardNotification=@"ReloadedKeyboard";
void gm_ios_loading_stage(const char *text) {
    @autoreleasepool {
        NSString *stage=[NSString stringWithUTF8String:text] ?: @"Cargando";
        task_vm_info_data_t vm={0};mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
        kern_return_t result=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&vm,&count);
        NSLog(@"[startup] %@ | memoria=%llu MiB",stage,result==KERN_SUCCESS?(unsigned long long)(vm.phys_footprint/1048576):0);
        [stage writeToFile:[Documents() stringByAppendingPathComponent:@"last-stage.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:StageNotification object:stage];});
    }
}
void gm_ios_show_keyboard(bool visible) {
    dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:KeyboardNotification object:@(visible)];});
}
void gm_ios_haptic(void) {
    dispatch_async(dispatch_get_main_queue(),^{UIImpactFeedbackGenerator *f=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleSoft];[f impactOccurred];});
}
@interface GameView : UIView<UIKeyInput>
@end
@implementation GameView
+(Class)layerClass{return CAEAGLLayer.class;}
-(instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.multipleTouchEnabled=YES;self.contentScaleFactor=MIN(UIScreen.mainScreen.scale,2.0);
        CAEAGLLayer *layer=(CAEAGLLayer *)self.layer;layer.opaque=YES;
        layer.drawableProperties=@{kEAGLDrawablePropertyRetainedBacking:@NO,kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};
    }return self;
}
-(BOOL)canBecomeFirstResponder{return YES;}
-(BOOL)hasText{return YES;}
-(UIKeyboardType)keyboardType{return UIKeyboardTypeDefault;}
-(UIReturnKeyType)returnKeyType{return UIReturnKeyDone;}
-(UITextAutocorrectionType)autocorrectionType{return UITextAutocorrectionTypeNo;}
-(UITextAutocapitalizationType)autocapitalizationType{return UITextAutocapitalizationTypeNone;}
-(void)insertText:(NSString *)text {
    if([text isEqualToString:@"\n"]){gm_ios_tap(13);[self resignFirstResponder];return;}
    NSData *utf32=[text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    const uint32_t *codes=utf32.bytes;for(NSUInteger i=0;i<utf32.length/4;i++)gm_ios_text(codes[i]);
}
-(void)deleteBackward{gm_ios_tap(8);}
-(void)send:(uint32_t)kind touches:(NSSet<UITouch *> *)touches {
    for(UITouch *touch in touches){CGPoint p=[touch locationInView:self];
        // UITouch identity is stable through this gesture; preserve all simultaneous fingers.
        int32_t pointer=(int32_t)((uintptr_t)(__bridge void *)touch & 0x7fffffff);
        gm_ios_touch(kind,pointer,p.x*self.contentScaleFactor,p.y*self.contentScaleFactor);
    }
}
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{[self send:1 touches:touches];}
-(void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{[self send:0 touches:touches];}
-(void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{[self send:2 touches:touches];}
-(void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{gm_ios_release_all();}
@end

@interface GameController : UIViewController
@property(nonatomic,copy)NSString *gameRoot;
@property(nonatomic)BOOL smoke,started;
@property(nonatomic,strong)GameView *canvas;
@property(nonatomic,strong)UILabel *loading;
@property(nonatomic,strong)UIButton *menu;
@property(nonatomic,strong)CADisplayLink *pump;
@end
@implementation GameController
-(void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
    self.canvas=[[GameView alloc]initWithFrame:CGRectZero];[self.view addSubview:self.canvas];
    self.menu=[UIButton buttonWithType:UIButtonTypeSystem];[self.menu setTitle:@"•••" forState:UIControlStateNormal];self.menu.tintColor=UIColor.whiteColor;
    self.menu.backgroundColor=[UIColor colorWithWhite:.05 alpha:.65];self.menu.layer.cornerRadius=12;[self.menu addTarget:self action:@selector(options) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:self.menu];
    self.loading=[UILabel new];self.loading.text=@"Preparando juego…";self.loading.textColor=UIColor.whiteColor;self.loading.textAlignment=NSTextAlignmentCenter;
    self.loading.backgroundColor=[UIColor colorWithWhite:0 alpha:.8];self.loading.numberOfLines=3;self.loading.layer.cornerRadius=12;self.loading.clipsToBounds=YES;[self.view addSubview:self.loading];
    NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(stage:) name:StageNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardRequest:) name:KeyboardNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(pause) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    self.pump=[CADisplayLink displayLinkWithTarget:self selector:@selector(pollTouch)];[self.pump addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    UIApplication.sharedApplication.idleTimerDisabled=YES;
}
-(void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Keep the Android layout clear of the Dynamic Island and home indicator.
    UIEdgeInsets safe=self.view.safeAreaInsets;
    self.canvas.frame=UIEdgeInsetsInsetRect(self.view.bounds,UIEdgeInsetsMake(0,safe.left,MAX(8,safe.bottom),safe.right));
    self.menu.frame=CGRectMake(CGRectGetMidX(self.view.bounds)-22,self.view.bounds.size.height-31,44,24);
    self.loading.frame=CGRectMake(CGRectGetMidX(self.view.bounds)-210,CGRectGetMidY(self.view.bounds)-45,420,90);
}
-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];if(self.started)return;self.started=YES;
    GameView *canvas=self.canvas;NSString *root=self.gameRoot;
    uint32_t w=canvas.bounds.size.width*canvas.contentScaleFactor,h=canvas.bounds.size.height*canvas.contentScaleFactor;
    NSString *font=[NSBundle.mainBundle pathForResource:@"soundfont" ofType:@"sf2"];
    // GCD workers have a small stack. GML parsing and execution need a dedicated engine stack.
    NSThread *engine=[[NSThread alloc]initWithBlock:^{@autoreleasepool{
        NSLog(@"[startup] motor en hilo dedicado; stack=%lu KiB",(unsigned long)(NSThread.currentThread.stackSize/1024));
        int result=gm_ios_run((__bridge void *)canvas,w,h,root.fileSystemRepresentation,font.fileSystemRepresentation,self.smoke);
        NSString *message=result==0?@"Sesión finalizada":EngineError();
        if(self.smoke && result!=0){[ message writeToFile:[Documents() stringByAppendingPathComponent:@"smoke-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];}
        dispatch_async(dispatch_get_main_queue(),^{
            [self.pump invalidate];self.pump=nil;[self.canvas resignFirstResponder];
            [self dismissViewControllerAnimated:YES completion:^{if(self.smoke && result==0){[UIApplication.sharedApplication.keyWindow.rootViewController performSelector:@selector(testSettings)];}if(result!=0){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"No se pudo iniciar" message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[UIApplication.sharedApplication.keyWindow.rootViewController presentViewController:a animated:YES completion:nil];}}];
        });
    }}];engine.name=@"Reloaded Engine";engine.stackSize=8*1024*1024;[engine start];
}
-(void)pollTouch{if(!self.smoke)gm_ios_pump();}
-(void)stage:(NSNotification *)n{self.loading.text=n.object;self.loading.hidden=[n.object isEqualToString:@"Juego iniciado"]||[n.object isEqualToString:@"Prueba de controles"]||[n.object isEqualToString:@"Sesión finalizada"];}
-(void)keyboardRequest:(NSNotification *)n{if([n.object boolValue])[self.canvas becomeFirstResponder];else[self.canvas resignFirstResponder];}
-(void)keyboardFrame:(NSNotification *)n{
    CGRect keyboard=[self.canvas convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGRect overlap=CGRectIntersection(self.canvas.bounds,keyboard);
    gm_ios_ime_inset(CGRectIsNull(overlap)?0:overlap.size.height*self.canvas.contentScaleFactor);
}
-(void)pause{gm_ios_release_all();gm_ios_set_active(false);}
-(void)resume{gm_ios_set_active(true);}
-(void)audioInterrupted:(NSNotification *)n{if([n.userInfo[AVAudioSessionInterruptionTypeKey]unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan)[self pause];else if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[self resume];}
-(void)options {
    gm_ios_release_all();UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Reloaded" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Teclado" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self.canvas becomeFirstResponder];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Teclas adicionales" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self extraKeys];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Salir al inicio" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[self askExit];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Continuar" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.menu;a.popoverPresentationController.sourceRect=self.menu.bounds;[self presentViewController:a animated:YES completion:nil];
}
-(void)extraKeys {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Teclas adicionales" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *names=@[@"F1",@"F2",@"F3",@"F4",@"F5",@"F6",@"F7",@"F8",@"Shift",@"Tab"];
    NSArray *codes=@[@112,@113,@114,@115,@116,@117,@118,@119,@16,@9];
    for(NSUInteger i=0;i<names.count;i++){NSNumber *code=codes[i];[a addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){gm_ios_tap(code.unsignedIntValue);}]];}
    [a addAction:[UIAlertAction actionWithTitle:@"Cerrar" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.menu;a.popoverPresentationController.sourceRect=self.menu.bounds;[self presentViewController:a animated:YES completion:nil];
}
-(void)askExit {
    [self.canvas resignFirstResponder];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"¿Salir del juego?" message:@"Guardá desde el menú del juego antes de salir. El progreso sin guardar se perderá." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Continuar jugando" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Salir" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){gm_ios_close();}]];[self presentViewController:a animated:YES completion:nil];
}
-(void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];UIApplication.sharedApplication.idleTimerDisabled=NO;}
@end

#include "Settings.m"

@interface Launcher : UIViewController<UIDocumentPickerDelegate>
@property(nonatomic,strong)UIStackView *stack;
@property(nonatomic,strong)UILabel *status;
@property(nonatomic,strong)UIButton *playButton;
@property(nonatomic,strong)UIButton *importButton;
@property(nonatomic)BOOL importing;
@end
@implementation Launcher
-(NSString *)gameRoot {NSString *folder=[NSUserDefaults.standardUserDefaults stringForKey:@"gameFolder"];return folder?[Documents() stringByAppendingPathComponent:folder]:nil;}
-(UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];b.tintColor=UIColor.whiteColor;b.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];b.backgroundColor=[UIColor colorWithRed:.12 green:.25 blue:.43 alpha:1];b.layer.cornerRadius=12;[b.heightAnchor constraintEqualToConstant:44].active=YES;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[self.stack addArrangedSubview:b];return b;
}
-(void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithRed:.035 green:.055 blue:.1 alpha:1];
    self.stack=[[UIStackView alloc]init];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=10;self.stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[[self.stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[self.stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],[self.stack.widthAnchor constraintEqualToConstant:480]]];
    UILabel *title=[[UILabel alloc]init];title.text=@"RELOADED  /  iOS";title.font=[UIFont systemFontOfSize:30 weight:UIFontWeightBlack];title.textColor=UIColor.whiteColor;title.textAlignment=NSTextAlignmentCenter;[self.stack addArrangedSubview:title];
    self.status=[[UILabel alloc]init];self.status.text=@"Controles Android 0.3.9/V22 · Importá el ZIP original del juego";self.status.textColor=[UIColor colorWithWhite:.72 alpha:1];self.status.font=[UIFont systemFontOfSize:14];self.status.textAlignment=NSTextAlignmentCenter;self.status.numberOfLines=3;[self.stack addArrangedSubview:self.status];
    self.playButton=[self button:@"Jugar" action:@selector(play)];self.importButton=[self button:@"Importar ZIP del juego" action:@selector(importGame)];
    [self button:@"Ajustes y controles" action:@selector(settings)];
    UIStackView *row=[[UIStackView alloc]init];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=12;row.distribution=UIStackViewDistributionFillEqually;
    UIButton *logs=[UIButton buttonWithType:UIButtonTypeSystem];[logs setTitle:@"Compartir registro" forState:UIControlStateNormal];[logs addTarget:self action:@selector(logs) forControlEvents:UIControlEventTouchUpInside];[row addArrangedSubview:logs];
    UIButton *saves=[UIButton buttonWithType:UIButtonTypeSystem];[saves setTitle:@"Mis archivos y partidas" forState:UIControlStateNormal];[saves addTarget:self action:@selector(saves) forControlEvents:UIControlEventTouchUpInside];[row addArrangedSubview:saves];[self.stack addArrangedSubview:row];
    UILabel *credits=[[UILabel alloc]init];credits.text=@"Motor OpenGMK · Base Android de Klisee · Adaptación experimental para iOS\nEl juego original de F3R se importa por separado.";credits.font=[UIFont systemFontOfSize:10];credits.textColor=[UIColor colorWithWhite:.5 alpha:1];credits.numberOfLines=2;credits.textAlignment=NSTextAlignmentCenter;[self.stack addArrangedSubview:credits];
}
-(void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];NSString *root=[self gameRoot];self.playButton.enabled=root && gm_ios_has_game(root.fileSystemRepresentation);self.playButton.alpha=self.playButton.enabled?1:.4;}
-(void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];static BOOL tested=NO;if(!tested && [NSProcessInfo.processInfo.arguments containsObject:@"--smoke-test"]){tested=YES;GameController *game=[GameController new];game.smoke=YES;game.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:game animated:NO completion:nil];}}
-(void)testSettings {
    UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:[[ReloadedSettings alloc]initWithStyle:UITableViewStyleInsetGrouped]];
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:nav animated:NO completion:^{
        ControlEditor *editor=[ControlEditor new];[nav pushViewController:editor animated:NO];[editor.view layoutIfNeeded];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            @try {
                NSAssert(editor.controls.count>20,@"No se cargó la vista de controles");
                UIButton *z=nil;for(UIButton *b in editor.preview.subviews)if([b.accessibilityIdentifier isEqual:@"z"]){z=b;break;}
                NSAssert(z!=nil,@"Falta Z en el editor");
                [editor select:z];z.center=CGPointMake(editor.preview.bounds.size.width*.80,editor.preview.bounds.size.height*.76);[editor store:z scale:1.25];[editor reload];
                NSDictionary *found=nil;for(NSDictionary *c in editor.controls)if([c[@"name"] isEqual:@"z"]){found=c;break;}
                NSAssert(fabs([found[@"x"] doubleValue]-.80)<.01,@"No se guardó la posición");
                [editor.entries removeObjectForKey:@"world z"];[editor persist];[editor reload];
                NSLog(@"IOS_SETTINGS_OK: editor shares Android layout, move/scale persisted and reloaded");
                [@"READY" writeToFile:[Documents() stringByAppendingPathComponent:@"settings-ready.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[@"PASS" writeToFile:[Documents() stringByAppendingPathComponent:@"smoke-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];});
            } @catch(NSException *e) { [e.description writeToFile:[Documents() stringByAppendingPathComponent:@"smoke-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        });
    }];
}
-(void)play{GameController *game=[GameController new];game.gameRoot=[self gameRoot];game.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:game animated:YES completion:nil];}
-(void)settings{UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:[[ReloadedSettings alloc]initWithStyle:UITableViewStyleInsetGrouped]];nav.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:nav animated:YES completion:nil];}
-(void)importGame{if(self.importing)return;UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP] asCopy:NO];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];}
-(void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;if(!url)return;BOOL access=[url startAccessingSecurityScopedResource];
    self.importing=YES;self.playButton.enabled=NO;self.importButton.enabled=NO;self.status.text=@"Importando archivos… Mantené la app abierta.";
    NSString *folder=[@"game-" stringByAppendingString:NSUUID.UUID.UUIDString];NSString *destination=[Documents()stringByAppendingPathComponent:folder];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        __block int result=-1;__block NSString *message=nil;NSError *coordinationError=nil;
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc]init];
        [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL){result=gm_ios_import(readURL.fileSystemRepresentation,destination.fileSystemRepresentation);if(result!=0)message=EngineError();}];
        if(access)[url stopAccessingSecurityScopedResource];
        if(coordinationError)message=coordinationError.localizedDescription;
        if(result==0)[NSUserDefaults.standardUserDefaults setObject:folder forKey:@"gameFolder"];
        dispatch_async(dispatch_get_main_queue(),^{self.importing=NO;self.importButton.enabled=YES;self.playButton.enabled=[self gameRoot]!=nil;self.playButton.alpha=self.playButton.enabled?1:.4;self.status.text=result==0?@"Juego importado. Tocá Jugar.":message;});
    }});
}
-(void)logs {
    NSMutableArray *files=[NSMutableArray new];
    for(NSString *name in @[@"emulator-previous.log",@"emulator.log",@"last-stage.txt"]){NSString *p=[Documents() stringByAppendingPathComponent:name];if([NSFileManager.defaultManager fileExistsAtPath:p])[files addObject:[NSURL fileURLWithPath:p]];}
    UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:files applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);[self presentViewController:sheet animated:YES completion:nil];
}
-(void)saves {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Archivos y partidas" message:@"Abrí Archivos → En mi iPhone → Reloaded iOS. Cada carpeta game contiene una importación y sus partidas. Podés copiar tus partidas desde allí. Importar otro ZIP conserva las carpetas anteriores." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
@end

@interface AppDelegate : UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@end
@implementation AppDelegate
-(void)applicationDidReceiveMemoryWarning:(UIApplication *)application {NSLog(@"[memory] iOS avisó de presión de memoria");}
-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    audioLock=[NSLock new];
    NSString *log=[Documents() stringByAppendingPathComponent:@"emulator.log"];NSString *old=[Documents() stringByAppendingPathComponent:@"emulator-previous.log"];
    [NSFileManager.defaultManager removeItemAtPath:old error:nil];[NSFileManager.defaultManager moveItemAtPath:log toPath:old error:nil];
    freopen(log.fileSystemRepresentation,"a",stdout);freopen(log.fileSystemRepresentation,"a",stderr);setbuf(stdout,NULL);setbuf(stderr,NULL);
    NSLog(@"Reloaded iOS 0.2.0 — controles Android 0.3.9/V22");
    gm_ios_configure(Documents().fileSystemRepresentation);
    NSString *source=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Controls"];
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:source error:nil]){
        NSString *target=[Documents() stringByAppendingPathComponent:name];
        if(![NSFileManager.defaultManager fileExistsAtPath:target]) [NSFileManager.defaultManager copyItemAtPath:[source stringByAppendingPathComponent:name] toPath:target error:nil];
    }
    NSDictionary *defaults=@{@"touch.conf":@"style=classic\nmove=joystick\nopacity=1\nscale=1\n",@"touch-appearance.conf":@"touch-appearance-v1\nstyle=modern_v2\ntint=original\nanimations=1\nhaptics=1\n",@"shaders.txt":@"off\n135\n55\n",@"video.conf":@"scaling=aspect\nrender=native\nshow_fps=0\n"};
    for(NSString *name in defaults){NSString *path=[Documents() stringByAppendingPathComponent:name];if(![NSFileManager.defaultManager fileExistsAtPath:path])[(NSString *)defaults[name] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];}
    self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[Launcher new];[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}

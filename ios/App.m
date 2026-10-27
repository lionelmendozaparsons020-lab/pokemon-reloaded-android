#import <UIKit/UIKit.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
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

@interface GameView : UIView<UIKeyInput>
@property(nonatomic)BOOL rightClick;
@property(nonatomic,strong)UITouch *pointer;
@end
@implementation GameView
+(Class)layerClass {return CAEAGLLayer.class;}
-(instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){self.multipleTouchEnabled=YES;self.contentScaleFactor=MIN(UIScreen.mainScreen.scale,2.0);
        CAEAGLLayer *layer=(CAEAGLLayer *)self.layer;layer.opaque=YES;layer.drawableProperties=@{kEAGLDrawablePropertyRetainedBacking:@NO,kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};}
    return self;
}
-(BOOL)canBecomeFirstResponder{return YES;}
-(BOOL)hasText{return YES;}
-(UIKeyboardType)keyboardType{return UIKeyboardTypeDefault;}
-(UIReturnKeyType)returnKeyType{return UIReturnKeyDone;}
-(UITextAutocorrectionType)autocorrectionType{return UITextAutocorrectionTypeNo;}
-(UITextAutocapitalizationType)autocapitalizationType{return UITextAutocapitalizationTypeNone;}
-(void)insertText:(NSString *)text {
    if([text isEqualToString:@"\n"]){gm_ios_key(13,true);gm_ios_key(13,false);[self resignFirstResponder];return;}
    NSData *utf32=[text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    const uint32_t *codes=utf32.bytes;for(NSUInteger i=0;i<utf32.length/4;i++)gm_ios_text(codes[i]);
}
-(void)deleteBackward{gm_ios_key(8,true);gm_ios_key(8,false);}
-(void)sendPointer:(uint32_t)kind touch:(UITouch *)touch {
    CGPoint p=[touch locationInView:self];gm_ios_pointer(kind,p.x*self.contentScaleFactor,p.y*self.contentScaleFactor,self.rightClick);
}
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {if(!self.pointer){self.pointer=touches.anyObject;[self sendPointer:1 touch:self.pointer];}}
-(void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {if(self.pointer && [touches containsObject:self.pointer])[self sendPointer:0 touch:self.pointer];}
-(void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {if(self.pointer && [touches containsObject:self.pointer]){[self sendPointer:2 touch:self.pointer];self.pointer=nil;}}
-(void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{[self touchesEnded:touches withEvent:event];}
@end

@interface DirectionPad : UIView
@property(nonatomic,strong)UITouch *tracked;
@property(nonatomic)uint8_t held;
-(void)releaseDirections;
@end
@implementation DirectionPad
-(instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){self.backgroundColor=[UIColor colorWithWhite:0.13 alpha:0.8];self.layer.cornerRadius=frame.size.width/2;self.multipleTouchEnabled=YES;
        UILabel *mark=[[UILabel alloc]initWithFrame:self.bounds];mark.text=@"✥";mark.font=[UIFont systemFontOfSize:70 weight:UIFontWeightLight];mark.textAlignment=NSTextAlignmentCenter;mark.textColor=UIColor.whiteColor;mark.userInteractionEnabled=NO;mark.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self addSubview:mark];}
    return self;
}
-(void)apply:(uint8_t)mask {uint32_t keys[]={37,39,38,40};for(int i=0;i<4;i++){BOOL old=(self.held&(1<<i))!=0;BOOL now=(mask&(1<<i))!=0;if(old!=now)gm_ios_key(keys[i],now);}self.held=mask;}
-(void)updateTouch:(UITouch *)touch {CGPoint p=[touch locationInView:self];CGFloat dx=(p.x-CGRectGetMidX(self.bounds))/(self.bounds.size.width/2),dy=(p.y-CGRectGetMidY(self.bounds))/(self.bounds.size.height/2);uint8_t mask=0;if(dx<-.22)mask|=1;if(dx>.22)mask|=2;if(dy<-.22)mask|=4;if(dy>.22)mask|=8;[self apply:mask];}
-(void)releaseDirections{[self apply:0];self.tracked=nil;}
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{if(!self.tracked){self.tracked=touches.anyObject;[self updateTouch:self.tracked];}}
-(void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{if(self.tracked && [touches containsObject:self.tracked])[self updateTouch:self.tracked];}
-(void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{if([touches containsObject:self.tracked])[self releaseDirections];}
-(void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{[self touchesEnded:touches withEvent:event];}
@end

@interface GameController : UIViewController
@property(nonatomic,copy)NSString *gameRoot;
@property(nonatomic)BOOL smoke;
@property(nonatomic)BOOL started;
@property(nonatomic,strong)GameView *canvas;
@property(nonatomic,strong)UIView *controls;
@property(nonatomic,strong)DirectionPad *pad;
@property(nonatomic,strong)UIView *extraKeys;
@property(nonatomic,strong)UIButton *mouseToggle;
@end
@implementation GameController
-(void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
    self.canvas=[[GameView alloc]initWithFrame:self.view.bounds];self.canvas.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.view addSubview:self.canvas];
    self.controls=[[UIView alloc]initWithFrame:self.view.bounds];self.controls.userInteractionEnabled=NO; // Buttons are added directly to the root; empty areas reach the canvas.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pause) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    self.pad=[[DirectionPad alloc]initWithFrame:CGRectMake(0,0,130,130)];[self.view addSubview:self.pad];
    for(NSArray *item in @[@[@"Z",@90],@[@"X",@88],@[@"C",@67],@[@"V",@86],@[@"A",@65],@[@"S",@83],@[@"D",@68],@[@"8",@56]])[self addKey:item[0] code:[item[1]unsignedIntValue] parent:self.view];
    [self addKey:@"Menú" code:27 parent:self.view];[self addKey:@"Enter" code:13 parent:self.view];[self addKey:@"Correr" code:16 parent:self.view];
    [self addAction:@"Teclado" action:@selector(keyboard) tag:1001];
    [self addAction:@"Más teclas" action:@selector(moreKeys) tag:1002];
    self.mouseToggle=[self addAction:@"Clic: izq." action:@selector(toggleMouse) tag:1003];
    [self addAction:@"Salir" action:@selector(askExit) tag:1004];
    self.extraKeys=[[UIView alloc]initWithFrame:CGRectZero];self.extraKeys.backgroundColor=[UIColor colorWithWhite:.04 alpha:.95];self.extraKeys.layer.cornerRadius=16;self.extraKeys.hidden=YES;[self.view addSubview:self.extraKeys];
    for(NSArray *item in @[@[@"1",@49],@[@"2",@50],@[@"3",@51],@[@"4",@52],@[@"5",@53],@[@"6",@54],@[@"7",@55],@[@"9",@57],@[@"0",@48],@[@"B",@66],@[@"E",@69],@[@"M",@77],@[@"Q",@81],@[@"R",@82],@[@"F",@70],@[@"Espacio",@32],@[@"Tab",@9],@[@"F1",@112],@[@"F2",@113],@[@"F3",@114],@[@"F4",@115],@[@"F5",@116],@[@"F6",@117],@[@"F7",@118]])[self addKey:item[0] code:[item[1]unsignedIntValue] parent:self.extraKeys];
    UIApplication.sharedApplication.idleTimerDisabled=YES;
}
-(UIButton *)addKey:(NSString *)name code:(uint32_t)code parent:(UIView *)parent {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.tag=code;[b setTitle:name forState:UIControlStateNormal];b.tintColor=UIColor.whiteColor;b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];b.backgroundColor=[UIColor colorWithWhite:.16 alpha:.85];b.layer.cornerRadius=14;
    [b addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
    [b addTarget:self action:@selector(keyUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];[parent addSubview:b];return b;
}
-(UIButton *)addAction:(NSString *)title action:(SEL)selector tag:(NSInteger)tag {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.tag=tag;[b setTitle:title forState:UIControlStateNormal];b.tintColor=UIColor.whiteColor;b.backgroundColor=[UIColor colorWithWhite:.08 alpha:.85];b.layer.cornerRadius=9;b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];[b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:b];return b;
}
-(void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);CGFloat x=safe.origin.x+10,y=CGRectGetMaxY(safe)-155;
    self.pad.frame=CGRectMake(x,y,130,130);CGFloat right=CGRectGetMaxX(safe)-136;
    NSArray *keys=@[@90,@88,@67,@86,@65,@83,@68,@56];for(NSUInteger i=0;i<keys.count;i++){UIView *b=[self.view viewWithTag:[keys[i]integerValue]];b.frame=CGRectMake(right+(i%2)*64,CGRectGetMaxY(safe)-235+(i/2)*56,58,50);}
    [self.view viewWithTag:27].frame=CGRectMake(x,CGRectGetMinY(safe)+48,64,44);
    [self.view viewWithTag:13].frame=CGRectMake(x+70,CGRectGetMinY(safe)+48,64,44);
    [self.view viewWithTag:16].frame=CGRectMake(x,CGRectGetMaxY(safe)-209,130,44);
    for(int i=0;i<4;i++)[self.view viewWithTag:1001+i].frame=CGRectMake(x+i*96,CGRectGetMinY(safe)+4,90,36);
    self.extraKeys.frame=CGRectMake(CGRectGetMidX(safe)-185,CGRectGetMidY(safe)-110,370,225);
    NSUInteger index=0;for(UIView *b in self.extraKeys.subviews){b.frame=CGRectMake(8+(index%6)*60,8+(index/6)*54,54,48);index++;}
}
-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];if(self.started)return;self.started=YES;
    [self.view layoutIfNeeded];GameView *canvas=self.canvas;
    uint32_t w=(uint32_t)(canvas.bounds.size.width*canvas.contentScaleFactor),h=(uint32_t)(canvas.bounds.size.height*canvas.contentScaleFactor);
    NSString *root=self.gameRoot ?: Documents();NSString *font=[NSBundle.mainBundle pathForResource:@"soundfont" ofType:@"sf2"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        int result=gm_ios_run((__bridge void *)canvas,w,h,root.fileSystemRepresentation,font.fileSystemRepresentation,self.smoke);
        NSString *message=result==0 ? @"Sesión finalizada" : EngineError();
        if(self.smoke){NSString *value=result==0?@"PASS":message;[value writeToFile:[Documents() stringByAppendingPathComponent:@"smoke-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];}
        dispatch_async(dispatch_get_main_queue(),^{[self dismissViewControllerAnimated:YES completion:^{if(result!=0){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Registro de la prueba" message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[UIApplication.sharedApplication.keyWindow.rootViewController presentViewController:a animated:YES completion:nil];}}];});
    }});
}
-(void)keyDown:(UIButton *)button{gm_ios_key((uint32_t)button.tag,true);}
-(void)keyUp:(UIButton *)button{gm_ios_key((uint32_t)button.tag,false);}
-(void)keyboard{if(self.canvas.isFirstResponder)[self.canvas resignFirstResponder];else[self.canvas becomeFirstResponder];}
-(void)moreKeys{gm_ios_release_all();self.extraKeys.hidden=!self.extraKeys.hidden;}
-(void)toggleMouse{gm_ios_release_all();self.canvas.rightClick=!self.canvas.rightClick;[self.mouseToggle setTitle:self.canvas.rightClick?@"Clic: der.":@"Clic: izq." forState:UIControlStateNormal];}
-(void)pause{[self.pad releaseDirections];gm_ios_release_all();gm_ios_set_active(false);}
-(void)resume{gm_ios_set_active(true);}
-(void)audioInterrupted:(NSNotification *)n{if([n.userInfo[AVAudioSessionInterruptionTypeKey]unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan)[self pause];else if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[self resume];}
-(void)askExit {
    [self.canvas resignFirstResponder];gm_ios_release_all();
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"¿Salir del juego?" message:@"Guardá desde el menú del juego antes de salir. El progreso sin guardar se perderá." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Continuar jugando" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Salir" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){gm_ios_close();}]];[self presentViewController:a animated:YES completion:nil];
}
-(void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];UIApplication.sharedApplication.idleTimerDisabled=NO;}
@end

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
    self.status=[[UILabel alloc]init];self.status.text=@"Versión experimental · Importá el ZIP original del juego";self.status.textColor=[UIColor colorWithWhite:.72 alpha:1];self.status.font=[UIFont systemFontOfSize:14];self.status.textAlignment=NSTextAlignmentCenter;self.status.numberOfLines=3;[self.stack addArrangedSubview:self.status];
    self.playButton=[self button:@"Jugar" action:@selector(play)];self.importButton=[self button:@"Importar ZIP del juego" action:@selector(importGame)];
    UIStackView *row=[[UIStackView alloc]init];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=12;row.distribution=UIStackViewDistributionFillEqually;
    UIButton *logs=[UIButton buttonWithType:UIButtonTypeSystem];[logs setTitle:@"Compartir registro" forState:UIControlStateNormal];[logs addTarget:self action:@selector(logs) forControlEvents:UIControlEventTouchUpInside];[row addArrangedSubview:logs];
    UIButton *saves=[UIButton buttonWithType:UIButtonTypeSystem];[saves setTitle:@"Mis archivos y partidas" forState:UIControlStateNormal];[saves addTarget:self action:@selector(saves) forControlEvents:UIControlEventTouchUpInside];[row addArrangedSubview:saves];[self.stack addArrangedSubview:row];
    UILabel *credits=[[UILabel alloc]init];credits.text=@"Motor OpenGMK · Base Android de Klisee · Adaptación experimental para iOS\nEl juego original de F3R se importa por separado.";credits.font=[UIFont systemFontOfSize:10];credits.textColor=[UIColor colorWithWhite:.5 alpha:1];credits.numberOfLines=2;credits.textAlignment=NSTextAlignmentCenter;[self.stack addArrangedSubview:credits];
}
-(void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];NSString *root=[self gameRoot];self.playButton.enabled=root && gm_ios_has_game(root.fileSystemRepresentation);self.playButton.alpha=self.playButton.enabled?1:.4;}
-(void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];static BOOL tested=NO;if(!tested && [NSProcessInfo.processInfo.arguments containsObject:@"--smoke-test"]){tested=YES;GameController *game=[GameController new];game.smoke=YES;game.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:game animated:NO completion:nil];}}
-(void)play{GameController *game=[GameController new];game.gameRoot=[self gameRoot];game.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:game animated:YES completion:nil];}
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
        dispatch_async(dispatch_get_main_queue(),^{self.importing=NO;self.importButton.enabled=YES;self.playButton.enabled=[self gameRoot]!=nil;self.playButton.alpha=self.playButton.enabled?1:.4;self.status.text=result==0?@"Juego importado. Listo para la prueba.":message;});
    }});
}
-(void)logs {
    NSURL *url=[NSURL fileURLWithPath:[Documents()stringByAppendingPathComponent:@"emulator.log"]];UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:@[url] applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);[self presentViewController:sheet animated:YES completion:nil];
}
-(void)saves {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Archivos y partidas" message:@"Abrí Archivos → En mi iPhone → Reloaded iOS. Cada carpeta game contiene una importación y sus partidas. Podés copiar tus partidas desde allí. Importar otro ZIP conserva las carpetas anteriores." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
@end

@interface AppDelegate : UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@end
@implementation AppDelegate
-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    audioLock=[NSLock new];
    NSString *log=[Documents() stringByAppendingPathComponent:@"emulator.log"];NSString *old=[Documents() stringByAppendingPathComponent:@"emulator-previous.log"];
    [NSFileManager.defaultManager removeItemAtPath:old error:nil];[NSFileManager.defaultManager moveItemAtPath:log toPath:old error:nil];
    freopen(log.fileSystemRepresentation,"a",stdout);freopen(log.fileSystemRepresentation,"a",stderr);setbuf(stdout,NULL);setbuf(stderr,NULL);
    NSLog(@"Reloaded iOS experimental 0.1.0");
    self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[Launcher new];[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}

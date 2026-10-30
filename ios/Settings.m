// Native editor for the same touch-layout-v1 file used by Android.
@interface ControlEditor : UIViewController
@property(nonatomic,strong)UIView *preview;
@property(nonatomic,strong)UISegmentedControl *profiles;
@property(nonatomic,strong)UISlider *sizeSlider;
@property(nonatomic,strong)UILabel *selectionLabel;
@property(nonatomic,strong)UIButton *selected;
@property(nonatomic,strong)NSMutableDictionary *entries;
@property(nonatomic,strong)NSArray *controls;
@end
@implementation ControlEditor
-(UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskLandscape;}
-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{return UIInterfaceOrientationLandscapeRight;}
-(void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];RequestOrientation(self,UIInterfaceOrientationMaskLandscape);}
-(void)done{[self dismissViewControllerAnimated:YES completion:nil];}
-(NSString *)profileName{return @[@"world",@"battle",@"dialog",@"character",@"choice",@"safari",@"menu_nav",@"menu"][self.profiles.selectedSegmentIndex];}
-(void)viewDidLoad{
    [super viewDidLoad];self.title=@"Distribución de controles";self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Listo" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.entries=[NSMutableDictionary new];
    NSString *saved=[NSString stringWithContentsOfFile:[Documents() stringByAppendingPathComponent:@"touch-layout.conf"] encoding:NSUTF8StringEncoding error:nil];
    for(NSString *line in [saved componentsSeparatedByString:@"\n"]){NSArray *f=[line componentsSeparatedByString:@" "];if(f.count==6)self.entries[[NSString stringWithFormat:@"%@ %@",f[0],f[1]]]=line;}
    self.profiles=[[UISegmentedControl alloc]initWithItems:@[@"Mapa",@"Batalla",@"Diálogo",@"Personaje",@"Elección",@"Safari",@"Listas",@"Menús"]];
    self.profiles.selectedSegmentIndex=0;[self.profiles addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];[self.view addSubview:self.profiles];
    self.preview=[UIView new];self.preview.backgroundColor=[UIColor colorWithRed:.06 green:.08 blue:.11 alpha:1];self.preview.layer.cornerRadius=10;self.preview.clipsToBounds=YES;[self.view addSubview:self.preview];
    self.sizeSlider=[UISlider new];self.sizeSlider.minimumValue=.5;self.sizeSlider.maximumValue=2;self.sizeSlider.value=1;self.sizeSlider.enabled=NO;[self.sizeSlider addTarget:self action:@selector(resize) forControlEvents:UIControlEventValueChanged];[self.view addSubview:self.sizeSlider];
    self.selectionLabel=[UILabel new];self.selectionLabel.font=[UIFont systemFontOfSize:12];self.selectionLabel.text=@"Arrastrá un botón. Ajustá su tamaño abajo.";[self.view addSubview:self.selectionLabel];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Restablecer" style:UIBarButtonItemStylePlain target:self action:@selector(reset)];
}
-(void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    self.profiles.frame=CGRectMake(safe.origin.x+10,safe.origin.y+5,safe.size.width-20,28);
    CGFloat ratio=safe.size.width/MAX(1,self.view.bounds.size.height-MAX(8,self.view.safeAreaInsets.bottom));
    CGFloat h=MAX(120,safe.size.height-95),w=MIN(safe.size.width-20,h*ratio);h=w/ratio;
    self.preview.frame=CGRectMake(CGRectGetMidX(safe)-w/2,safe.origin.y+40,w,h);
    self.selectionLabel.frame=CGRectMake(safe.origin.x+16,CGRectGetMaxY(safe)-42,280,30);
    self.sizeSlider.frame=CGRectMake(safe.origin.x+300,CGRectGetMaxY(safe)-42,MAX(100,safe.size.width-320),30);
    [self reload];
}
-(void)persist{
    NSMutableString *s=[NSMutableString stringWithString:@"touch-layout-v1\n"];
    for(NSString *key in [[self.entries allKeys] sortedArrayUsingSelector:@selector(compare:)])[s appendFormat:@"%@\n",self.entries[key]];
    [s writeToFile:[Documents() stringByAppendingPathComponent:@"touch-layout.conf"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
-(void)reload{
    self.selected=nil;self.sizeSlider.enabled=NO;
    for(UIView *v in self.preview.subviews)[v removeFromSuperview];
    // Rust defines MENU as bit 0; the UI puts Menús last.
    const uint8_t contexts[]={2,4,8,16,32,64,128,1};
    char json[32768]={0};gm_ios_layout_json(contexts[self.profiles.selectedSegmentIndex],self.preview.bounds.size.width,self.preview.bounds.size.height,json,sizeof(json));
    self.controls=[NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    for(NSDictionary *c in self.controls){if(![c[@"active"] boolValue])continue;
        UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.accessibilityIdentifier=c[@"name"];
        CGFloat w=self.preview.bounds.size.width,h=self.preview.bounds.size.height;
        b.frame=CGRectMake(([c[@"x"] floatValue]-[c[@"rx"] floatValue])*w,([c[@"y"] floatValue]-[c[@"ry"] floatValue])*h,[c[@"rx"] floatValue]*2*w,[c[@"ry"] floatValue]*2*h);
        NSString *file=[c[@"name"] isEqual:@"joystick"]?@"joystick-base":c[@"name"];
        NSString *scoped=[NSString stringWithFormat:@"%@__%@",[self profileName],file];
        UIImage *art=[UIImage imageWithContentsOfFile:[Documents() stringByAppendingPathComponent:[scoped stringByAppendingString:@".png"]]];
        if(!art)art=[UIImage imageWithContentsOfFile:[Documents() stringByAppendingPathComponent:[file stringByAppendingString:@".png"]]];
        if(art){[b setImage:art forState:UIControlStateNormal];b.imageView.contentMode=UIViewContentModeScaleAspectFit;}
        else{[b setTitle:c[@"name"] forState:UIControlStateNormal];b.titleLabel.font=[UIFont boldSystemFontOfSize:9];b.backgroundColor=UIColor.darkGrayColor;b.layer.cornerRadius=10;}
        [b addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(drag:)]];
        [self.preview addSubview:b];
    }
}
-(void)select:(UIButton *)b{
    self.selected.layer.borderWidth=0;self.selected=b;b.layer.borderColor=UIColor.systemYellowColor.CGColor;b.layer.borderWidth=2;
    self.selectionLabel.text=[NSString stringWithFormat:@"%@ · arrastrá para mover",b.accessibilityIdentifier];
    NSString *line=self.entries[[NSString stringWithFormat:@"%@ %@",[self profileName],b.accessibilityIdentifier]];
    NSArray *fields=[line componentsSeparatedByString:@" "];self.sizeSlider.value=fields.count==6?[fields[4] floatValue]:1;self.sizeSlider.enabled=YES;
}
-(void)store:(UIButton *)b scale:(float)scale{
    CGFloat x=MIN(1,MAX(0,b.center.x/self.preview.bounds.size.width)),y=MIN(1,MAX(0,b.center.y/self.preview.bounds.size.height));
    NSString *key=[NSString stringWithFormat:@"%@ %@",[self profileName],b.accessibilityIdentifier];
    self.entries[key]=[NSString stringWithFormat:@"%@ %.5f %.5f %.3f 1",key,x,y,scale];[self persist];
}
-(void)drag:(UIPanGestureRecognizer *)g{
    UIButton *b=(UIButton *)g.view;if(g.state==UIGestureRecognizerStateBegan)[self select:b];
    CGPoint delta=[g translationInView:self.preview];b.center=CGPointMake(MIN(self.preview.bounds.size.width,MAX(0,b.center.x+delta.x)),MIN(self.preview.bounds.size.height,MAX(0,b.center.y+delta.y)));[g setTranslation:CGPointZero inView:self.preview];
    if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled)[self store:b scale:self.sizeSlider.value];
}
-(void)resize{
    if(!self.selected)return;NSString *name=self.selected.accessibilityIdentifier;float value=self.sizeSlider.value;
    [self store:self.selected scale:value];[self reload];
    for(UIButton *b in self.preview.subviews)if([b.accessibilityIdentifier isEqual:name]){[self select:b];break;}
}
-(void)reset{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Restablecer este perfil" message:@"Se restaurarán las posiciones y tamaños originales de Android." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restablecer" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSString *prefix=[[self profileName] stringByAppendingString:@" "];for(NSString *key in [self.entries.allKeys copy])if([key hasPrefix:prefix])[self.entries removeObjectForKey:key];[self persist];[self reload];
    }]];[self presentViewController:a animated:YES completion:nil];
}
@end


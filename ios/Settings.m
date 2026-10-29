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
-(NSString *)profileName{return @[@"world",@"battle",@"dialog",@"character",@"choice",@"safari",@"menu_nav",@"menu"][self.profiles.selectedSegmentIndex];}
-(void)viewDidLoad{
    [super viewDidLoad];self.title=@"Distribución de controles";self.view.backgroundColor=UIColor.systemBackgroundColor;
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

@interface ReloadedSettings : UITableViewController
@end
@implementation ReloadedSettings
-(void)viewDidLoad{
    [super viewDidLoad];self.title=@"Ajustes";self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Listo" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"touchStyle":@1,@"touchOpacity":@100,@"touchAnimations":@YES,@"touchHaptics":@YES,@"stretch":@NO,@"showFPS":@NO,@"renderRate":@0,@"shaders":@0}];
}
-(void)done{[self dismissViewControllerAnimated:YES completion:nil];}
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?5:section==1?4:1;}
-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"Controles de Android",@"Imagen y rendimiento",@"Archivos"][section];}
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    NSArray *labels=ip.section==0?@[@"Estilo",@"Editar posiciones y tamaños",@"Opacidad",@"Animaciones",@"Vibración"]:ip.section==1?@[@"Estirar pantalla",@"Mostrar FPS",@"Límite de dibujo",@"Shaders y sombras"]:@[@"Partidas y controles en Archivos"];
    c.textLabel.text=labels[ip.row];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if(ip.section==0&&ip.row==0)c.detailTextLabel.text=@[@"Moderno",@"Moderno V2",@"Clásico"][[d integerForKey:@"touchStyle"]];
    if(ip.section==0&&ip.row==2)c.detailTextLabel.text=[NSString stringWithFormat:@"%ld%%",(long)[d integerForKey:@"touchOpacity"]];
    if(ip.section==1&&ip.row==2)c.detailTextLabel.text=@[@"Nativo",@"60 FPS",@"120 FPS"][[d integerForKey:@"renderRate"]];
    if(ip.section==1&&ip.row==3)c.detailTextLabel.text=@[@"Desactivados",@"Suaves",@"Completos"][[d integerForKey:@"shaders"]];
    NSString *key=ip.section==0?(ip.row==3?@"touchAnimations":ip.row==4?@"touchHaptics":nil):(ip.section==1?(ip.row==0?@"stretch":ip.row==1?@"showFPS":nil):nil);
    if(key){UISwitch *s=[UISwitch new];s.on=[d boolForKey:key];s.accessibilityIdentifier=key;[s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
    return c;
}
-(void)save{
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    NSDictionary *files=@{
        @"touch.conf":[NSString stringWithFormat:@"style=classic\nmove=joystick\nscale=1\nopacity=%.2f\n",[d integerForKey:@"touchOpacity"]/100.0],
        @"touch-appearance.conf":[NSString stringWithFormat:@"touch-appearance-v1\nstyle=%@\ntint=original\nanimations=%d\nhaptics=%d\n",@[@"modern",@"modern_v2",@"classic"][[d integerForKey:@"touchStyle"]],[d boolForKey:@"touchAnimations"],[d boolForKey:@"touchHaptics"]],
        @"video.conf":[NSString stringWithFormat:@"scaling=%@\nrender=%@\nshow_fps=%d\n",[d boolForKey:@"stretch"]?@"full":@"aspect",@[@"native",@"60",@"120"][[d integerForKey:@"renderRate"]],[d boolForKey:@"showFPS"]],
        @"shaders.txt":[NSString stringWithFormat:@"%@\n135\n55\n",@[@"off",@"lite",@"high"][[d integerForKey:@"shaders"]]]
    };
    for(NSString *name in files)[(NSString *)files[name] writeToFile:[Documents() stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self.tableView reloadData];
}
-(void)toggle:(UISwitch *)s{[NSUserDefaults.standardUserDefaults setBool:s.on forKey:s.accessibilityIdentifier];[self save];}
-(void)choose:(NSArray *)titles values:(NSArray *)values key:(NSString *)key{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Elegir" message:nil preferredStyle:UIAlertControllerStyleAlert];
    for(NSUInteger i=0;i<titles.count;i++){id value=values[i];[a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[NSUserDefaults.standardUserDefaults setObject:value forKey:key];[self save];}]];}
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0&&ip.row==0)[self choose:@[@"Moderno",@"Moderno V2",@"Clásico"] values:@[@0,@1,@2] key:@"touchStyle"];
    else if(ip.section==0&&ip.row==1)[self.navigationController pushViewController:[ControlEditor new] animated:YES];
    else if(ip.section==0&&ip.row==2)[self choose:@[@"25%",@"50%",@"75%",@"100%"] values:@[@25,@50,@75,@100] key:@"touchOpacity"];
    else if(ip.section==1&&ip.row==2)[self choose:@[@"Nativo",@"60 FPS",@"120 FPS"] values:@[@0,@1,@2] key:@"renderRate"];
    else if(ip.section==1&&ip.row==3)[self choose:@[@"Desactivados",@"Suaves",@"Completos"] values:@[@0,@1,@2] key:@"shaders"];
    else if(ip.section==2){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tus archivos" message:@"Archivos → En mi iPhone → Reloaded iOS. Las carpetas game contienen el juego y sus partidas. touch-layout.conf guarda la distribución en el mismo formato que Android." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
}
@end


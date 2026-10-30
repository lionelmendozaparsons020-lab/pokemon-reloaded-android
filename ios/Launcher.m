@interface Launcher:UIViewController<UIDocumentPickerDelegate>
@property(nonatomic,strong)UIScrollView *scroll;
@property(nonatomic,strong)UIStackView *stack;
@property(nonatomic,strong)UIView *header,*dock,*nav;
@property(nonatomic,strong)UILabel *heading;
@property(nonatomic,copy)NSString *page,*notice;
@property(nonatomic,strong)NSDictionary *post,*metadata;
@property(nonatomic)BOOL importing,newsLoading,smokeStarted;
@property(nonatomic)NSInteger pickerKind,saveSlot;
@property(nonatomic,strong)NSURL *pendingSave;
-(void)testSettings;
@end
@implementation Launcher
-(UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskPortrait;}
-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{return UIInterfaceOrientationPortrait;}
-(BOOL)prefersStatusBarHidden{return NO;}
-(UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
-(NSString *)gameRoot{return GameRootPath();}
-(void)viewDidLoad{
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.page=@"home";
    RegisterPreferences();self.post=[NSDictionary dictionaryWithContentsOfFile:[Documents() stringByAppendingPathComponent:@"news-cache.plist"]];
    self.metadata=[NSDictionary dictionaryWithContentsOfFile:[Documents() stringByAppendingPathComponent:@"game-metadata.plist"]];
    [self render];[self refreshMetadata];
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--smoke-test"])[self fetchNews];
}
-(void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self render];}
-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];RequestOrientation(self,UIInterfaceOrientationMaskPortrait);
    if(!self.smokeStarted&&[NSProcessInfo.processInfo.arguments containsObject:@"--smoke-test"]){self.smokeStarted=YES;[self runLauncherTests];}
}
-(void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height,top=self.view.safeAreaInsets.top,bottom=self.view.safeAreaInsets.bottom;
    self.header.frame=CGRectMake(0,0,w,top+68);self.heading.frame=CGRectMake([self isRootPage]?24:56,top+12,w-([self.page isEqual:@"home"]?150:80),44);
    for(UIView *v in self.header.subviews){if(v.tag==101)v.frame=CGRectMake(8,top+12,44,44);else if(v.tag==102||v.tag==103)v.frame=CGRectMake(w-112+(v.tag-102)*54,top+10,48,48);}
    BOOL home=[self.page isEqual:@"home"];CGFloat dockHeight=home?222+bottom:0;
    self.dock.frame=CGRectMake(0,h-dockHeight,w,dockHeight);self.scroll.frame=CGRectMake(0,top+68,w,h-top-68-dockHeight);
    self.nav.frame=CGRectMake((w-MIN(252,w-64))/2,h-bottom-82,MIN(252,w-64),74);
    UIStackView *bar=(UIStackView *)self.nav.subviews.firstObject;bar.frame=CGRectInset(self.nav.bounds,8,8);
}
-(BOOL)isRootPage{return [@[@"home",@"settings",@"logs"] containsObject:self.page];}
-(void)go:(NSString *)page{self.page=page;[self render];}
-(void)back{[self go:[self.page isEqual:@"backups"]?@"saves":@"settings"];}
-(void)refresh{CGPoint offset=self.scroll.contentOffset;[self render];[self.view layoutIfNeeded];self.scroll.contentOffset=offset;}
-(void)render{
    for(UIView *v in [self.view.subviews copy])[v removeFromSuperview];__weak Launcher *weak=self;
    self.header=[UIView new];self.header.backgroundColor=[UIColor colorWithWhite:.085 alpha:1];[self.view addSubview:self.header];
    NSDictionary *titles=@{@"home":@"Pokemon Reloaded",@"settings":@"Ajustes",@"logs":@"Registros",@"fps":@"FPS",@"saves":@"Mis partidas",@"touch":@"Controles táctiles",@"shaders":@"Shaders y sombras",@"language":@"Seleccionar idioma",@"mods":@"Mods y Cheats",@"backups":@"Copias de seguridad",@"about":@"Acerca de"};
    self.heading=Label(titles[self.page]?:@"Ajustes",24,NO);self.heading.numberOfLines=1;self.heading.adjustsFontSizeToFitWidth=YES;[self.header addSubview:self.heading];
    if(![self isRootPage]){UIButton *back=ActionButton(@"",@"arrow.left",^{[weak back];});back.tag=101;back.frame=CGRectMake(8,self.view.safeAreaInsets.top+15,44,44);[self.header addSubview:back];}
    if([self.page isEqual:@"home"]){NSArray *icons=@[@"doc.text.fill",@"gearshape.fill"];for(NSInteger i=0;i<2;i++){UIButton *b=ActionButton(@"",icons[i],^{[weak go:i==0?@"logs":@"settings"];});b.tag=102+i;UIButtonConfiguration *c=b.configuration;c.baseForegroundColor=UIColor.whiteColor;b.configuration=c;b.backgroundColor=CardColor();b.layer.cornerRadius=24;b.frame=CGRectMake(self.view.bounds.size.width-112+i*54,self.view.safeAreaInsets.top+10,48,48);[self.header addSubview:b];}}
    self.scroll=[UIScrollView new];self.scroll.alwaysBounceVertical=YES;self.scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self.view insertSubview:self.scroll belowSubview:self.header];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=22;self.stack.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.stack];
    BOOL home=[self.page isEqual:@"home"];
    [NSLayoutConstraint activateConstraints:@[[self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:12],[self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:24],[self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-24],[self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:home?-24:-120],[self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-48]]];
    if(home)[self homeContent];else if([self.page isEqual:@"settings"])[self settingsContent];else if([self.page isEqual:@"fps"])[self fpsContent];else if([self.page isEqual:@"saves"])[self savesContent];else if([self.page isEqual:@"touch"])[self touchContent];else if([self.page isEqual:@"language"])[self languageContent];else if([self.page isEqual:@"shaders"])[self shadersContent];else if([self.page isEqual:@"mods"])[self modsContent];else if([self.page isEqual:@"backups"])[self backupsContent];else if([self.page isEqual:@"about"])[self aboutContent];else [self logsContent];
    self.dock=[UIView new];self.dock.backgroundColor=[UIColor colorWithWhite:.22 alpha:1];[self.view addSubview:self.dock];if(home)[self homeDock];
    self.nav=[UIView new];self.nav.backgroundColor=[UIColor colorWithRed:.19 green:.29 blue:.49 alpha:1];self.nav.layer.cornerRadius=37;[self.view addSubview:self.nav];
    UIStackView *bar=[UIStackView new];bar.axis=UILayoutConstraintAxisHorizontal;bar.spacing=2;[self.nav addSubview:bar];NSArray *pages=@[@"home",@"logs",@"settings"],*names=@[@"Inicio",@"Registros",@"Ajustes"],*icons=@[@"house.fill",@"doc.text",@"gearshape"];
    NSInteger selected=home?0:[self.page isEqual:@"logs"]?1:2;
    for(NSInteger i=0;i<3;i++){UIButton *b=ActionButton(i==selected?names[i]:@"",icons[i],^{[weak go:pages[i]];});UIButtonConfiguration *c=b.configuration;c.baseForegroundColor=UIColor.whiteColor;b.configuration=c;b.backgroundColor=i==selected?Accent():UIColor.clearColor;b.layer.cornerRadius=29;[bar addArrangedSubview:b];if(i!=selected)[b.widthAnchor constraintEqualToConstant:48].active=YES;}
    [self.view setNeedsLayout];
}
-(UIStackView *)group:(NSString *)title{
    UIStackView *section=[UIStackView new];section.axis=UILayoutConstraintAxisVertical;section.spacing=12;
    if(title.length){UILabel *l=Label(title,18,YES);l.textColor=Accent();[section addArrangedSubview:l];}
    UIStackView *rows=[UIStackView new];rows.axis=UILayoutConstraintAxisVertical;rows.spacing=2;rows.layer.cornerRadius=26;rows.clipsToBounds=YES;[section addArrangedSubview:rows];[self.stack addArrangedSubview:section];return rows;
}
-(AppRow *)row:(UIStackView *)group icon:(NSString *)icon title:(NSString *)title detail:(NSString *)detail action:(void(^)(void))block{
    AppRow *r=[[AppRow alloc]initWithIcon:icon title:title detail:detail accessory:nil action:block];[group addArrangedSubview:r];return r;
}
-(void)choice:(UIStackView *)group title:(NSString *)title detail:(NSString *)detail selected:(BOOL)selected action:(void(^)(void))block{
    AppRow *r=[[AppRow alloc]initWithIcon:[self.page isEqual:@"fps"]?@"speedometer":@"rectangle.expand.vertical" title:title detail:detail accessory:Radio(selected) action:block];r.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);[group addArrangedSubview:r];
}
-(void)toggle:(UIStackView *)group title:(NSString *)title detail:(NSString *)detail icon:(NSString *)icon key:(NSString *)key{
    UISwitch *s=[UISwitch new];s.on=[NSUserDefaults.standardUserDefaults boolForKey:key];s.onTintColor=Accent();s.accessibilityLabel=title;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a){[NSUserDefaults.standardUserDefaults setBool:[(UISwitch *)a.sender isOn] forKey:key];WritePreferences();}] forControlEvents:UIControlEventValueChanged];
    AppRow *r=[[AppRow alloc]initWithIcon:icon title:title detail:detail accessory:s action:nil];r.isAccessibilityElement=NO;[group addArrangedSubview:r];
}
-(void)message:(NSString *)title text:(NSString *)text{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Aceptar" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
-(void)openURL:(NSString *)string{NSURL *url=[NSURL URLWithString:string];if([url.scheme.lowercaseString isEqual:@"https"])[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];}
-(void)homeContent{
    __weak Launcher *weak=self;
    if(self.notice.length){UILabel *l=Label(self.notice,14,NO);l.textColor=Accent();[self.stack addArrangedSubview:l];}
    if(!self.post){[self.stack addArrangedSubview:Label(self.newsLoading?@"Cargando noticias…":@"Noticias de Pokémon Reloaded",26,NO)];[self.stack addArrangedSubview:Label(@"Aquí aparece la última publicación del blog oficial. Puedes jugar sin conexión si ya importaste el juego.",17,NO)];[self.stack addArrangedSubview:ActionButton(@"Actualizar noticias",@"arrow.clockwise",^{[weak fetchNews];})];return;}
    [self.stack addArrangedSubview:Label(self.post[@"title"],26,NO)];
    NSString *date=self.post[@"published"];if(date.length>=10){NSDateFormatter *f=[NSDateFormatter new];f.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US_POSIX"];f.dateFormat=@"yyyy-MM-dd";UILabel *l=Label([@"Publicado el " stringByAppendingString:FormatDate([f dateFromString:[date substringToIndex:10]])],16,YES);l.textColor=Accent();[self.stack addArrangedSubview:l];}
    NSString *imageURL=[self.post[@"images"] firstObject];if(imageURL){UIImageView *v=[UIImageView new];v.contentMode=UIViewContentModeScaleAspectFill;v.clipsToBounds=YES;v.layer.cornerRadius=44;v.backgroundColor=CardColor();[v.heightAnchor constraintEqualToConstant:200].active=YES;[self.stack addArrangedSubview:v];
        NSURL *url=[NSURL URLWithString:imageURL];if([url.scheme isEqual:@"https"])[[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){if(data.length>0&&data.length<12*1024*1024){UIImage *image=[UIImage imageWithData:data];dispatch_async(dispatch_get_main_queue(),^{v.image=image;});}}] resume];}
    UILabel *body=Label(self.post[@"summary"],18,NO);NSMutableParagraphStyle *p=[NSMutableParagraphStyle new];p.lineSpacing=6;body.attributedText=[[NSAttributedString alloc]initWithString:self.post[@"summary"]?:@"" attributes:@{NSFontAttributeName:AppFont(18,NO),NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:p}];[self.stack addArrangedSubview:body];
    [self.stack addArrangedSubview:ActionButton(@"Leer la entrada completa",@"arrow.up.right",^{[weak openURL:weak.post[@"url"]];})];
}
-(void)homeDock{
    __weak Launcher *weak=self;UIButton *play=ActionButton(self.importing?@"Importando…":@"Jugar",@"play.fill",^{[weak play];});play.backgroundColor=Accent();play.layer.cornerRadius=37;UIButtonConfiguration *c=play.configuration;c.baseForegroundColor=UIColor.whiteColor;c.attributedTitle=[[NSAttributedString alloc]initWithString:self.importing?@"Importando…":@"Jugar" attributes:@{NSFontAttributeName:AppFont(24,NO)}];play.configuration=c;play.titleLabel.font=AppFont(24,NO);play.enabled=!self.importing&&GameRootPath()!=nil;play.alpha=play.enabled?1:.45;play.translatesAutoresizingMaskIntoConstraints=NO;[self.dock addSubview:play];
    UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionFillEqually;row.translatesAutoresizingMaskIntoConstraints=NO;[row addArrangedSubview:ActionButton(@"Descargar",@"arrow.down.to.line",^{[weak openURL:@"https://pokemon-reloaded.blogspot.com/"];})];UIButton *import=ActionButton(@"Importar",@"folder",^{[weak importGame];});import.enabled=!self.importing;[row addArrangedSubview:import];[self.dock addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[play.topAnchor constraintEqualToAnchor:self.dock.topAnchor constant:24],[play.leadingAnchor constraintEqualToAnchor:self.dock.leadingAnchor constant:24],[play.trailingAnchor constraintEqualToAnchor:self.dock.trailingAnchor constant:-24],[play.heightAnchor constraintEqualToConstant:74],[row.topAnchor constraintEqualToAnchor:play.bottomAnchor constant:8],[row.leadingAnchor constraintEqualToAnchor:play.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:play.trailingAnchor],[row.heightAnchor constraintEqualToConstant:48]]];
}
-(void)fetchNews{
    if(self.newsLoading)return;self.newsLoading=YES;if([self.page isEqual:@"home"])[self render];
    NSURL *url=[NSURL URLWithString:@"https://pokemon-reloaded.blogspot.com/feeds/posts/default?alt=json&max-results=1"];NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.timeoutInterval=20;[request setValue:@"ReloadedLauncher-iOS/0.3" forHTTPHeaderField:@"User-Agent"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){NSDictionary *post=data.length<8*1024*1024?ParsePost(data):nil;
        dispatch_async(dispatch_get_main_queue(),^{self.newsLoading=NO;if(post){self.post=post;[post writeToFile:[Documents() stringByAppendingPathComponent:@"news-cache.plist"] atomically:YES];}else if(!self.post)self.notice=@"No se pudieron cargar las noticias. Puedes reintentar con conexión.";if([self.page isEqual:@"home"])[self refresh];});}] resume];
}
-(void)refreshMetadata{
    NSString *root=GameRootPath();if(!root)return;if([self.metadata[@"folder"] isEqual:root.lastPathComponent])return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        unsigned long long bytes=0;NSString *version=@"Sin datos";NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"[0-9]+\\.[0-9]+(?:\\.[0-9]+){1,2}" options:0 error:nil];
        NSDirectoryEnumerator *e=[NSFileManager.defaultManager enumeratorAtPath:root];NSString *rel;
        while((rel=[e nextObject])){NSDictionary *a=[e fileAttributes];if([a[NSFileType] isEqual:NSFileTypeRegular])bytes+=[a[NSFileSize] unsignedLongLongValue];if([rel.pathExtension.lowercaseString isEqual:@"exe"]){NSTextCheckingResult *m=[re firstMatchInString:rel options:0 range:NSMakeRange(0,rel.length)];if(m)version=[rel substringWithRange:m.range];}}
        NSDate *date=[NSFileManager.defaultManager attributesOfItemAtPath:root error:nil][NSFileCreationDate]?:NSDate.date;
        NSDictionary *m=@{@"folder":root.lastPathComponent,@"version":version,@"bytes":@(bytes),@"installed":date};
        dispatch_async(dispatch_get_main_queue(),^{if([GameRootPath() isEqual:root]){self.metadata=m;[m writeToFile:[Documents() stringByAppendingPathComponent:@"game-metadata.plist"] atomically:YES];if([self.page isEqual:@"settings"])[self refresh];}});
    });
}
-(void)settingsContent{
    __weak Launcher *w=self;NSUserDefaults *d=NSUserDefaults.standardUserDefaults;UIStackView *g=[self group:@"Juego"];
    if(GameRootPath()){
        [self row:g icon:@"gamecontroller.fill" title:@"Versión" detail:self.metadata[@"version"]?:@"Leyendo…" action:nil];
        [self row:g icon:@"internaldrive" title:@"Tamaño en disco" detail:self.metadata?FormatBytes(self.metadata[@"bytes"]):@"Calculando…" action:nil];
        [self row:g icon:@"calendar" title:@"Instalado el" detail:FormatDate(self.metadata[@"installed"]) action:nil];
        [self row:g icon:@"trash.fill" title:@"Borrar el juego" detail:@"Exporta tus partidas antes de eliminarlo" action:^{[w deleteGame];}];
    }else [self row:g icon:@"gamecontroller" title:@"Sin juego instalado" detail:@"Importa el ZIP desde Inicio" action:^{[w go:@"home"];}];
    g=[self group:@"Idioma"];NSString *language=[d stringForKey:@"gameLanguage"];[self row:g icon:@"globe" title:@"Seleccionar idioma" detail:[language isEqual:@"es"]?@"Español":[language isEqual:@"en"]?@"English":@"Automático" action:^{[w go:@"language"];}];
    g=[self group:@"Partidas"];[self row:g icon:@"externaldrive.fill" title:@"Mis partidas" detail:@"Ve cuáles partidas tienes guardadas en el juego" action:^{[w go:@"saves"];}];
    g=[self group:@"Mods"];[self row:g icon:@"clock.arrow.circlepath" title:@"Mods y Cheats" detail:@"Trucos oficiales F3 y respaldos de partidas" action:^{[w go:@"mods"];}];
    g=[self group:@"Controles táctiles"];[self row:g icon:@"hand.draw" title:@"Controles táctiles" detail:@"Estilo, transparencia y distribución de botones" action:^{[w go:@"touch"];}];
    g=[self group:@"Shaders"];[self row:g icon:@"sun.max" title:@"Shaders y sombras" detail:@[@"Desactivados",@"Suaves",@"Completos"][PrefIndex(@"shaders",3)] action:^{[w go:@"shaders"];}];
    g=[self group:@"Resolución"];
    [self choice:g title:@"Rellenar la pantalla" detail:@"La imagen ocupa todo el móvil, aunque se deforme un poco" selected:[d boolForKey:@"stretch"] action:^{[d setBool:YES forKey:@"stretch"];WritePreferences();[w refresh];}];
    [self choice:g title:@"Mantener la proporción" detail:@"El aspecto clásico del PC, con bandas oscuras a los lados" selected:![d boolForKey:@"stretch"] action:^{[d setBool:NO forKey:@"stretch"];WritePreferences();[w refresh];}];
    g=[self group:@"FPS"];[self row:g icon:@"speedometer" title:@"FPS" detail:@"Modifica el framerate del juego a tu gusto, con frames mayores a 30 FPS" action:^{[w go:@"fps"];}];
    g=[self group:@"Pantalla"];[self toggle:g title:@"Mantener la pantalla encendida" detail:@"Evita que el móvil se bloquee mientras juegas" icon:@"sun.max.fill" key:@"keepAwake"];
    g=[self group:@"Ayuda"];[self row:g icon:@"doc.text" title:@"Compartir registro" detail:@"Comparte los logs si ocurre un error" action:^{[w logs];}];[self row:g icon:@"info.circle" title:@"Acerca de" detail:@"Versión 0.3.0 · Créditos" action:^{[w go:@"about"];}];
}
-(void)fpsContent{
    __weak Launcher *w=self;UIStackView *g=[self group:@""];[self toggle:g title:@"Mostrar FPS en el juego" detail:@"Muestra los fotogramas dibujados por segundo" icon:@"eye" key:@"showFPS"];
    g=[self group:@"FPS"];NSArray *titles=@[@"30 FPS (Original)",@"60 FPS (Experimental)",@"120 FPS (Experimental)",@"FPS sin Límite"];
    NSArray *details=@[@"La forma clásica y original de jugar Pokémon Reloaded, con un fotograma por paso del juego.",@"Dibuja hasta 60 fotogramas por segundo para mejorar la fluidez. Conserva la velocidad original del juego.",@"Dibuja hasta 120 fotogramas por segundo en pantallas compatibles. El rendimiento depende del dispositivo y de la escena.",@"El motor dibuja sin un límite fijo. Los fotogramas visibles siguen dependiendo de la pantalla; no acelera la lógica del juego."];
    for(NSInteger i=0;i<4;i++){[self choice:g title:titles[i] detail:details[i] selected:PrefIndex(@"renderRate",4)==i action:^{[NSUserDefaults.standardUserDefaults setInteger:i forKey:@"renderRate"];WritePreferences();[w refresh];}];}
    [self.stack addArrangedSubview:Label([NSString stringWithFormat:@"Pantalla detectada: hasta %ld Hz. Los cambios se aplican al volver a abrir el juego.",(long)UIScreen.mainScreen.maximumFramesPerSecond],14,NO)];
}
-(void)languageContent{__weak Launcher *w=self;UIStackView *g=[self group:@"Idioma del juego"];NSArray *names=@[@"Automático",@"Español",@"English"],*values=@[@"auto",@"es",@"en"];for(NSInteger i=0;i<3;i++)[self choice:g title:names[i] detail:@"Se aplica al iniciar el juego" selected:[[NSUserDefaults.standardUserDefaults stringForKey:@"gameLanguage"] isEqual:values[i]] action:^{[NSUserDefaults.standardUserDefaults setObject:values[i] forKey:@"gameLanguage"];[w refresh];}];}
-(void)shadersContent{__weak Launcher *w=self;UIStackView *g=[self group:@"Shaders y sombras"];NSArray *names=@[@"Desactivados",@"Suaves",@"Completos"],*details=@[@"Imagen original y menor carga gráfica",@"Mejoras suaves de color e iluminación",@"Iluminación y sombras V22; requiere más rendimiento"];for(NSInteger i=0;i<3;i++)[self choice:g title:names[i] detail:details[i] selected:PrefIndex(@"shaders",3)==i action:^{[NSUserDefaults.standardUserDefaults setInteger:i forKey:@"shaders"];WritePreferences();[w refresh];}];[self.stack addArrangedSubview:Label(@"El cambio se aplicará la próxima vez que abras el juego.",16,NO)];}
-(void)touchContent{
    __weak Launcher *w=self;UIStackView *g=[self group:@"Estilo"];NSArray *names=@[@"Moderno",@"Moderno V2",@"Clásico"];for(NSInteger i=0;i<3;i++)[self choice:g title:names[i] detail:@"Arte y controles de la versión Android" selected:PrefIndex(@"touchStyle",3)==i action:^{[NSUserDefaults.standardUserDefaults setInteger:i forKey:@"touchStyle"];WritePreferences();[w refresh];}];
    g=[self group:@"Distribución"];[self row:g icon:@"hand.draw" title:@"Editar controles" detail:@"Mueve botones y ajusta su tamaño para cada pantalla del juego" action:^{ControlEditor *e=[ControlEditor new];OrientationNavigationController *n=[[OrientationNavigationController alloc]initWithRootViewController:e];n.modalPresentationStyle=UIModalPresentationFullScreen;[w presentViewController:n animated:YES completion:nil];}];
    g=[self group:@"Opacidad"];for(NSNumber *value in @[@25,@50,@75,@100])[self choice:g title:[NSString stringWithFormat:@"%@%%",value] detail:@"" selected:[NSUserDefaults.standardUserDefaults integerForKey:@"touchOpacity"]==value.integerValue action:^{[NSUserDefaults.standardUserDefaults setObject:value forKey:@"touchOpacity"];WritePreferences();[w refresh];}];
    g=[self group:@"Respuesta"];[self toggle:g title:@"Animaciones" detail:@"Animación al tocar los controles" icon:@"sparkles" key:@"touchAnimations"];[self toggle:g title:@"Vibración" detail:@"Respuesta táctil al pulsar" icon:@"iphone.radiowaves.left.and.right" key:@"touchHaptics"];
}
-(void)modsContent{__weak Launcher *w=self;UIStackView *g=[self group:@"Trucos oficiales"];[self toggle:g title:@"Mostrar botón F3" detail:@"Abre la consola de trucos del juego desde el mapa" icon:@"terminal" key:@"officialF3"];g=[self group:@"Respaldos"];[self row:g icon:@"externaldrive" title:@"Mis partidas" detail:@"Exporta una copia antes de utilizar trucos" action:^{[w go:@"saves"];}];[self row:g icon:@"clock.arrow.circlepath" title:@"Copias de seguridad" detail:@"Respaldos creados antes de importar partidas" action:^{[w go:@"backups"];}];}
-(void)savesContent{
    __weak Launcher *w=self;if(!GameDirectory()){[self.stack addArrangedSubview:Label(@"Primero importa el ZIP del juego desde Inicio.",18,NO)];return;}
    for(NSDictionary *s in SaveSlots()){NSInteger slot=[s[@"index"] integerValue];BOOL used=[s[@"used"] boolValue];UIStackView *g=[self group:[NSString stringWithFormat:@"Partida %ld",(long)slot]];
        NSString *summary=used?[NSString stringWithFormat:@"%@\nVistos: %@ · Capturados: %@\n%@",[s[@"name"] length]?s[@"name"]:@"Partida guardada",s[@"seen"],s[@"caught"],s[@"place"]]:@"Ranura vacía";
        [self row:g icon:@"externaldrive.fill" title:[NSString stringWithFormat:@"Slot %ld",(long)slot] detail:summary action:nil];
        if(used)[self row:g icon:@"square.and.arrow.up" title:@"Exportar partida" detail:@"Guardar o compartir un ZIP" action:^{[w exportSaves:slot];}];
        [self row:g icon:@"square.and.arrow.down" title:@"Importar partida" detail:@"Restaurar un ZIP en esta ranura" action:^{[w selectSaveImport:slot];}];
    }
    UIStackView *g=[self group:@"Todas las partidas"];[self row:g icon:@"square.and.arrow.up" title:@"Exportar todas las partidas" detail:@"Incluye partidas, equipos y personajes personalizados" action:^{[w exportSaves:0];}];[self row:g icon:@"square.and.arrow.down" title:@"Importar todas las partidas" detail:@"Compatible con los ZIP de Android y PC" action:^{[w selectSaveImport:0];}];[self row:g icon:@"clock.arrow.circlepath" title:@"Copias de seguridad" detail:@"Se crea una copia antes de cada restauración" action:^{[w go:@"backups"];}];
}
-(void)shareFiles:(NSArray *)urls{if(!urls.count){[self message:@"Sin archivos" text:@"Todavía no hay archivos para compartir."];return;}UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:urls applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);[self presentViewController:sheet animated:YES completion:nil];}
-(void)exportSaves:(NSInteger)slot{
    if(self.importing)return;self.importing=YES;NSString *root=GameRootPath();NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];NSString *path=[dir stringByAppendingPathComponent:slot?[NSString stringWithFormat:@"partida%ld.zip",(long)slot]:@"partidas-reloaded.zip"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{int result=gm_ios_saves(root.fileSystemRepresentation,path.fileSystemRepresentation,(uint32_t)slot,false);NSString *error=result?EngineError():nil;dispatch_async(dispatch_get_main_queue(),^{self.importing=NO;if(result)[self message:@"No se pudo exportar" text:error];else [self shareFiles:@[[NSURL fileURLWithPath:path]]];});});
}
-(void)selectSaveImport:(NSInteger)slot{if(self.importing)return;self.pickerKind=1;self.saveSlot=slot;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}
-(void)confirmSaveImport:(NSURL *)url{
    self.pendingSave=url;UIAlertController *a=[UIAlertController alertControllerWithTitle:self.saveSlot?[NSString stringWithFormat:@"¿Importar en la partida %ld?",(long)self.saveSlot]:@"¿Importar todas las partidas?" message:@"Los archivos del ZIP reemplazarán los que coincidan. Primero se guardará una copia de tus partidas actuales." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x){self.pendingSave=nil;}]];[a addAction:[UIAlertAction actionWithTitle:@"Importar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self restoreSaves:url];}]];[self presentViewController:a animated:YES completion:nil];
}
-(void)restoreSaves:(NSURL *)url{
    if(self.importing)return;self.importing=YES;NSString *root=GameRootPath();NSInteger slot=self.saveSlot;self.notice=@"Importando partidas…";[self refresh];BOOL access=[url startAccessingSecurityScopedResource];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString *error=nil;BOOL hasFiles=NO;NSString *data=[GameDirectory() stringByAppendingPathComponent:@"data"];
        for(NSString *f in @[@"partidas",@"equipos",@"char_custom"]){NSDirectoryEnumerator *en=[NSFileManager.defaultManager enumeratorAtPath:[data stringByAppendingPathComponent:f]];for(NSString *rel in en){if([en.fileAttributes[NSFileType] isEqual:NSFileTypeRegular]){hasFiles=YES;break;}}}
        if(hasFiles){NSString *backups=[Documents() stringByAppendingPathComponent:@"SaveBackups"];[NSFileManager.defaultManager createDirectoryAtPath:backups withIntermediateDirectories:YES attributes:nil error:nil];NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd_HH-mm-ss";NSString *name=[NSString stringWithFormat:@"partidas-%@-%@.zip",[f stringFromDate:NSDate.date],[NSUUID.UUID.UUIDString substringToIndex:6]];NSString *backup=[backups stringByAppendingPathComponent:name];if(gm_ios_saves(root.fileSystemRepresentation,backup.fileSystemRepresentation,0,false)!=0)error=EngineError();}
        int result=-1;if(!error){result=gm_ios_saves(root.fileSystemRepresentation,url.fileSystemRepresentation,(uint32_t)slot,true);if(result)error=EngineError();}if(access)[url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{self.importing=NO;self.pendingSave=nil;self.notice=nil;[self refresh];[self message:result==0?@"Partidas importadas":@"No se pudo importar" text:result==0?@"La restauración terminó. Tus archivos anteriores están en Copias de seguridad.":error];});
    });
}
-(void)backupsContent{__weak Launcher *w=self;NSString *folder=[Documents() stringByAppendingPathComponent:@"SaveBackups"];NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(compare:)];UIStackView *g=[self group:@"Respaldos anteriores"];if(!names.count)[self row:g icon:@"clock.arrow.circlepath" title:@"Todavía no hay copias automáticas" detail:@"Se crean antes de importar partidas cuando ya existen archivos guardados." action:nil];for(NSString *name in names.reverseObjectEnumerator){if(![name.pathExtension isEqual:@"zip"])continue;[self row:g icon:@"archivebox" title:name detail:@"Toca para guardar o compartir el ZIP" action:^{[w shareFiles:@[[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]]]];}];}}
-(void)play{if(self.importing)return;WritePreferences();WriteGameLanguage();GameController *game=[GameController new];game.gameRoot=GameRootPath();game.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:game animated:YES completion:nil];}
-(void)importGame{if(self.importing)return;self.pickerKind=0;UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP] asCopy:NO];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}
-(void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    NSURL *url=urls.firstObject;if(!url)return;if(self.pickerKind==1){[controller dismissViewControllerAnimated:YES completion:^{[self confirmSaveImport:url];}];return;}
    BOOL access=[url startAccessingSecurityScopedResource];self.importing=YES;self.notice=@"Importando el juego… Mantén la app abierta.";[self render];NSString *folder=[@"game-" stringByAppendingString:NSUUID.UUID.UUIDString];NSString *destination=[Documents() stringByAppendingPathComponent:folder];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{__block int result=-1;__block NSString *message=nil;NSError *coordinationError=nil;NSFileCoordinator *c=[NSFileCoordinator new];[c coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL){result=gm_ios_import(readURL.fileSystemRepresentation,destination.fileSystemRepresentation);if(result)message=EngineError();}];if(access)[url stopAccessingSecurityScopedResource];if(coordinationError)message=coordinationError.localizedDescription;
        dispatch_async(dispatch_get_main_queue(),^{self.importing=NO;if(result==0){[NSUserDefaults.standardUserDefaults setObject:folder forKey:@"gameFolder"];self.metadata=nil;[self refreshMetadata];self.notice=@"Juego importado. Ya puedes jugar.";}else self.notice=message;[self render];});
    });
}
-(void)deleteGame{if(self.importing)return;NSString *root=GameRootPath();if(!root)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"¿Borrar el juego?" message:@"Se borrará esta instalación, incluidas sus partidas. Exporta una copia primero. Los ZIP de Copias de seguridad se conservarán." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Borrar" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){NSError *e=nil;if([NSFileManager.defaultManager removeItemAtPath:root error:&e]){[NSUserDefaults.standardUserDefaults removeObjectForKey:@"gameFolder"];self.metadata=nil;[NSFileManager.defaultManager removeItemAtPath:[Documents() stringByAppendingPathComponent:@"game-metadata.plist"] error:nil];[self render];}else [self message:@"No se pudo borrar" text:e.localizedDescription];}]];[self presentViewController:a animated:YES completion:nil];}
-(void)logs{NSMutableArray *files=[NSMutableArray new];for(NSString *name in @[@"emulator-previous.log",@"emulator.log",@"last-stage.txt"]){NSString *p=[Documents() stringByAppendingPathComponent:name];if([NSFileManager.defaultManager fileExistsAtPath:p])[files addObject:[NSURL fileURLWithPath:p]];}[self shareFiles:files];}
-(void)logsContent{__weak Launcher *w=self;[self.stack addArrangedSubview:ActionButton(@"Compartir registro",@"square.and.arrow.up",^{[w logs];})];NSString *text=[NSString stringWithContentsOfFile:[Documents() stringByAppendingPathComponent:@"emulator.log"] encoding:NSUTF8StringEncoding error:nil]?:@"Todavía no hay registros.";if(text.length>10000)text=[text substringFromIndex:text.length-10000];UILabel *l=Label(text,11,NO);l.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];[self.stack addArrangedSubview:l];}
-(void)aboutContent{[self.stack addArrangedSubview:Label(@"Pokémon Reloaded para iOS\nVersión 0.3.0",24,YES)];[self.stack addArrangedSubview:Label(@"Motor OpenGMK. Base Android de Klisee. Pokémon Reloaded y su blog pertenecen a sus autores. El juego se importa por separado.\n\nInterfaz nativa de iOS basada en la versión Android; los diálogos para abrir y compartir archivos son los del sistema.",17,NO)];}
// End-to-end checks use synthetic files only; never run on a normal launch.
-(void)failTest:(NSException *)e{[e.description writeToFile:[Documents() stringByAppendingPathComponent:@"smoke-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];}
-(void)markTest:(NSString *)name{[@"READY" writeToFile:[Documents() stringByAppendingPathComponent:[name stringByAppendingString:@"-ready.txt"]] atomically:YES encoding:NSUTF8StringEncoding error:nil];}
-(void)runLauncherTests{
    @try{
        NSAssert(self.view.bounds.size.height>self.view.bounds.size.width,@"Inicio no está en vertical");
        NSAssert(!ParsePost(nil)&&!ParsePost([@"{\"feed\":null}" dataUsingEncoding:NSUTF8StringEncoding]),@"Feed inválido no rechazado");
        NSDictionary *feed=@{@"feed":@{@"entry":@[@{@"title":@{@"$t":@"Noticias de prueba"},@"content":@{@"$t":@"<p>Publicación de prueba del lector de noticias.</p>"},@"published":@{@"$t":@"2026-10-29"}}]}};
        self.post=ParsePost([NSJSONSerialization dataWithJSONObject:feed options:0 error:nil]);NSAssert([self.post[@"title"] isEqual:@"Noticias de prueba"],@"No se leyó el feed");
        NSString *root=[Documents() stringByAppendingPathComponent:@"launcher-test"];
        NSString *saves=[root stringByAppendingPathComponent:@"data/partidas"];
        [NSFileManager.defaultManager createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:nil];
        [@"MZ" writeToFile:[root stringByAppendingPathComponent:@"Reloaded-1.9.2.2.exe"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"SYNTHETIC SAVE" writeToFile:[saves stringByAppendingPathComponent:@"reloaded1.savc"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"Entrenador de prueba\n10\n5\nLugar de prueba" writeToFile:[saves stringByAppendingPathComponent:@"reloaded1.nfo"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [NSUserDefaults.standardUserDefaults setObject:@"launcher-test" forKey:@"gameFolder"];
        NSString *zip=[NSTemporaryDirectory() stringByAppendingPathComponent:@"test-save-export.zip"];
        NSAssert(gm_ios_saves(root.fileSystemRepresentation,zip.fileSystemRepresentation,1,false)==0,@"Exportación nativa falló");
        NSAssert(gm_ios_saves(root.fileSystemRepresentation,zip.fileSystemRepresentation,3,true)==0,@"Importación nativa falló");
        NSArray *slots=SaveSlots();NSAssert([slots[0][@"name"] isEqual:@"Entrenador de prueba"]&&[slots[2][@"used"] boolValue],@"Ranuras incorrectas");
        NSLog(@"IOS_SAVES_OK: native export/import, slot transfer, original preserved and metadata parsed");
        [self refreshMetadata];[self render];[self markTest:@"launcher"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            @try{
                [self go:@"fps"];
                for(NSInteger i=0;i<4;i++){[NSUserDefaults.standardUserDefaults setInteger:i forKey:@"renderRate"];WritePreferences();NSString *c=[NSString stringWithContentsOfFile:[Documents() stringByAppendingPathComponent:@"video.conf"] encoding:NSUTF8StringEncoding error:nil];NSAssert([c containsString:[@"render=" stringByAppendingString:@[@"native",@"60",@"120",@"uncapped"][i]]],@"No se guardó FPS");}
                [NSUserDefaults.standardUserDefaults setInteger:1 forKey:@"renderRate"];[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"stretch"];WritePreferences();[self render];[self markTest:@"fps"];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{GameController *game=[GameController new];game.smoke=YES;game.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:game animated:NO completion:nil];});
            }@catch(NSException *e){[self failTest:e];}
        });
    }@catch(NSException *e){[self failTest:e];}
}
-(void)testSettings{
    [self go:@"settings"];RequestOrientation(self,UIInterfaceOrientationMaskPortrait);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        @try{NSAssert(self.view.bounds.size.height>self.view.bounds.size.width,@"No volvió a vertical");NSLog(@"IOS_LAUNCHER_OK: portrait launcher, news parser, four FPS modes, landscape game and portrait return");[self markTest:@"options"];}
        @catch(NSException *e){[self failTest:e];return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self go:@"saves"];[self markTest:@"saves"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self testEditor];});
        });
    });
}
-(void)testEditor{
    ControlEditor *editor=[ControlEditor new];OrientationNavigationController *nav=[[OrientationNavigationController alloc]initWithRootViewController:editor];nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:nav animated:NO completion:^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        @try{
            [editor.view layoutIfNeeded];NSAssert(editor.view.bounds.size.width>editor.view.bounds.size.height,@"Editor no está horizontal");NSAssert(editor.controls.count>20,@"Faltan controles");
            UIButton *z=nil;for(UIButton *b in editor.preview.subviews)if([b.accessibilityIdentifier isEqual:@"z"]){z=b;break;}NSAssert(z,@"Falta Z");
            [editor select:z];z.center=CGPointMake(editor.preview.bounds.size.width*.8,editor.preview.bounds.size.height*.76);[editor store:z scale:1.25];[editor reload];
            NSDictionary *found=nil;for(NSDictionary *c in editor.controls)if([c[@"name"] isEqual:@"z"]){found=c;break;}NSAssert(fabs([found[@"x"] doubleValue]-.8)<.01,@"No se guardó la posición");
            [editor.entries removeObjectForKey:@"world z"];[editor persist];[editor reload];NSLog(@"IOS_SETTINGS_OK: editor shares Android layout, move/scale persisted and reloaded");[self markTest:@"settings"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[@"PASS" writeToFile:[Documents() stringByAppendingPathComponent:@"smoke-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];});
        }@catch(NSException *e){[self failTest:e];}
    });}];
}
@end

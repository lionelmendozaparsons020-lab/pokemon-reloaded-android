// Shared native UI and persistent launcher data. No game assets are bundled here.
static UIColor *Accent(void){return [UIColor colorWithRed:55/255.0 green:120/255.0 blue:255/255.0 alpha:1];}
static UIColor *CardColor(void){return [UIColor colorWithRed:76/255.0 green:75/255.0 blue:80/255.0 alpha:1];}
static UIFont *AppFont(CGFloat size,BOOL bold){UIFont *f=[UIFont fontWithName:@"GoogleSansFlex-Regular" size:size] ?: [UIFont systemFontOfSize:size];if(bold)f=[UIFont fontWithDescriptor:[f.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute:@{UIFontWeightTrait:@(UIFontWeightSemibold)}}] size:size];return f;}
static UILabel *Label(NSString *text,CGFloat size,BOOL bold){UILabel *l=[UILabel new];l.text=text;l.font=AppFont(size,bold);l.textColor=UIColor.whiteColor;l.numberOfLines=0;return l;}
static NSString *GameRootPath(void){NSString *folder=[NSUserDefaults.standardUserDefaults stringForKey:@"gameFolder"];return folder.length?[Documents() stringByAppendingPathComponent:folder]:nil;}
static NSString *GameDirectory(void){
    NSString *root=GameRootPath();if(!root)return nil;
    NSDirectoryEnumerator *e=[NSFileManager.defaultManager enumeratorAtPath:root];NSString *rel;NSString *fallback=nil;
    while((rel=[e nextObject])){if([rel.lastPathComponent isEqual:@"data"]){[e skipDescendants];continue;}if(![rel.pathExtension.lowercaseString isEqual:@"exe"])continue;
        NSString *dir=[[root stringByAppendingPathComponent:rel] stringByDeletingLastPathComponent];BOOL isDir=NO;
        if([NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:@"data"] isDirectory:&isDir]&&isDir){if([rel.lowercaseString containsString:@"reload"])return dir;fallback=dir;}}
    return fallback;
}
static NSInteger PrefIndex(NSString *key,NSInteger count){return MAX(0,MIN(count-1,[NSUserDefaults.standardUserDefaults integerForKey:key]));}
static void RegisterPreferences(void){[NSUserDefaults.standardUserDefaults registerDefaults:@{@"touchStyle":@1,@"touchOpacity":@100,@"touchAnimations":@YES,@"touchHaptics":@YES,@"stretch":@NO,@"showFPS":@NO,@"renderRate":@0,@"shaders":@0,@"keepAwake":@YES,@"gameLanguage":@"auto",@"officialF3":@NO}];}
static void WritePreferences(void){
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    NSDictionary *files=@{
        @"touch.conf":[NSString stringWithFormat:@"style=classic\nmove=joystick\nscale=1\nopacity=%.2f\n",MAX(0,MIN(100,[d integerForKey:@"touchOpacity"]))/100.0],
        @"touch-appearance.conf":[NSString stringWithFormat:@"touch-appearance-v1\nstyle=%@\ntint=original\nanimations=%d\nhaptics=%d\n",@[@"modern",@"modern_v2",@"classic"][PrefIndex(@"touchStyle",3)],[d boolForKey:@"touchAnimations"],[d boolForKey:@"touchHaptics"]],
        @"video.conf":[NSString stringWithFormat:@"scaling=%@\nrender=%@\nshow_fps=%d\n",[d boolForKey:@"stretch"]?@"full":@"aspect",@[@"native",@"60",@"120",@"uncapped"][PrefIndex(@"renderRate",4)],[d boolForKey:@"showFPS"]],
        @"mods.conf":[NSString stringWithFormat:@"official_f3=%d\n",[d boolForKey:@"officialF3"]],
        @"shaders.txt":[NSString stringWithFormat:@"%@\n135\n55\n",@[@"off",@"lite",@"high"][PrefIndex(@"shaders",3)]]};
    for(NSString *name in files)[files[name] writeToFile:[Documents() stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void WriteGameLanguage(void){NSString *dir=GameDirectory();if(!dir)return;NSString *language=[NSUserDefaults.standardUserDefaults stringForKey:@"gameLanguage"];
    if([language isEqual:@"auto"])language=[NSLocale.preferredLanguages.firstObject hasPrefix:@"es"]?@"es":@"en";
    NSString *folder=[dir stringByAppendingPathComponent:@"data/text"];[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *value=[language isEqual:@"en"]?@" 1":@" 0";[value writeToFile:[folder stringByAppendingPathComponent:@"config.ini"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void RequestOrientation(UIViewController *controller,UIInterfaceOrientationMask mask){
    [controller setNeedsUpdateOfSupportedInterfaceOrientations];[controller.navigationController setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene *scene=controller.view.window.windowScene;
    if(scene)[scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc]initWithInterfaceOrientations:mask] errorHandler:^(NSError *e){NSLog(@"[orientation] %@",e.localizedDescription);}];
}
@interface OrientationNavigationController:UINavigationController @end
@implementation OrientationNavigationController
-(UIInterfaceOrientationMask)supportedInterfaceOrientations{return self.topViewController.supportedInterfaceOrientations;}
-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{return self.topViewController.preferredInterfaceOrientationForPresentation;}
@end

@interface AppRow:UIControl
@property(nonatomic,copy)void(^action)(void);
@end
@implementation AppRow
-(instancetype)initWithIcon:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail accessory:(UIView *)accessory action:(void(^)(void))action {
    if((self=[super initWithFrame:CGRectZero])){self.action=action;self.backgroundColor=CardColor();self.accessibilityLabel=title;self.isAccessibilityElement=YES;
        UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:symbol]];icon.tintColor=UIColor.whiteColor;icon.contentMode=UIViewContentModeScaleAspectFit;icon.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:icon];
        UIStackView *text=[[UIStackView alloc]init];text.axis=UILayoutConstraintAxisVertical;text.spacing=4;text.userInteractionEnabled=NO;text.translatesAutoresizingMaskIntoConstraints=NO;[text addArrangedSubview:Label(title,18,YES)];if(detail.length)[text addArrangedSubview:Label(detail,16,NO)];[self addSubview:text];
        [NSLayoutConstraint activateConstraints:@[[self.heightAnchor constraintGreaterThanOrEqualToConstant:74],[icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],[icon.topAnchor constraintEqualToAnchor:self.topAnchor constant:23],[icon.widthAnchor constraintEqualToConstant:24],[icon.heightAnchor constraintEqualToConstant:24],[text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:18],[text.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],[text.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-17]]];
        if(accessory){accessory.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:accessory];[NSLayoutConstraint activateConstraints:@[[accessory.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],[accessory.topAnchor constraintEqualToAnchor:self.topAnchor constant:19],[text.trailingAnchor constraintEqualToAnchor:accessory.leadingAnchor constant:-14]]];}
        else [text.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20].active=YES;
        [self addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
    }return self;
}
-(void)activate{if(self.action)self.action();}
@end
static UIImageView *Radio(BOOL selected){UIImageView *v=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:selected?@"largecircle.fill.circle":@"circle"]];v.tintColor=selected?Accent():UIColor.whiteColor;[v.widthAnchor constraintEqualToConstant:23].active=YES;[v.heightAnchor constraintEqualToConstant:23].active=YES;return v;}
static UIButton *ActionButton(NSString *title,NSString *symbol,void(^block)(void)){
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];c.attributedTitle=[[NSAttributedString alloc]initWithString:title attributes:@{NSFontAttributeName:AppFont(17,YES)}];c.image=[UIImage systemImageNamed:symbol];c.imagePadding=10;c.baseForegroundColor=Accent();b.configuration=c;b.titleLabel.font=AppFont(17,YES);[b addAction:[UIAction actionWithHandler:^(UIAction *a){block();}] forControlEvents:UIControlEventTouchUpInside];return b;
}
static NSString *PlainHTML(NSString *html){
    NSString *s=html?:@"";
    for(NSArray *rule in @[@[@"(?is)<(script|style)[^>]*>.*?</\\1>",@""],@[@"(?i)<br\\s*/?>|</p>|</div>|</h[1-6]>",@"\n"],@[@"<[^>]+>",@""]]){NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:rule[0] options:0 error:nil];s=[r stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0,s.length) withTemplate:rule[1]];}
    NSDictionary *entities=@{@"&nbsp;":@" ",@"&amp;":@"&",@"&quot;":@"\"",@"&#39;":@"'",@"&apos;":@"'",@"&lt;":@"<",@"&gt;":@">",@"&aacute;":@"á",@"&eacute;":@"é",@"&iacute;":@"í",@"&oacute;":@"ó",@"&uacute;":@"ú",@"&ntilde;":@"ñ",@"&iexcl;":@"¡",@"&iquest;":@"¿"};for(NSString *k in entities)s=[s stringByReplacingOccurrencesOfString:k withString:entities[k]];
    NSMutableArray *lines=[NSMutableArray new];for(NSString *line in [s componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSString *t=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(t.length)[lines addObject:t];}return [lines componentsJoinedByString:@"\n"];
}
static NSDictionary *ParsePost(NSData *data){
    if(!data.length)return nil;
    NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(![json isKindOfClass:NSDictionary.class])return nil;
    id feed=json[@"feed"];if(![feed isKindOfClass:NSDictionary.class])return nil;
    id entries=feed[@"entry"];if(![entries isKindOfClass:NSArray.class]||![entries count])return nil;NSDictionary *e=[entries firstObject];
    if(![e isKindOfClass:NSDictionary.class]||![e[@"title"] isKindOfClass:NSDictionary.class]||![e[@"content"] isKindOfClass:NSDictionary.class])return nil;
    NSString *title=e[@"title"][@"$t"],*html=e[@"content"][@"$t"];if(![title isKindOfClass:NSString.class]||![html isKindOfClass:NSString.class])return nil;
    NSString *url=@"https://pokemon-reloaded.blogspot.com/";if([e[@"link"] isKindOfClass:NSArray.class])for(NSDictionary *link in e[@"link"])if([link isKindOfClass:NSDictionary.class]&&[link[@"rel"] isEqual:@"alternate"]&&[link[@"href"] isKindOfClass:NSString.class]&&[link[@"href"] hasPrefix:@"https://"])url=link[@"href"];
    NSMutableArray *images=[NSMutableArray new];NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:@"<img[^>]+src=[\"']([^\"']+)[\"']" options:NSRegularExpressionCaseInsensitive error:nil];
    for(NSTextCheckingResult *m in [r matchesInString:html options:0 range:NSMakeRange(0,html.length)]){NSString *src=[html substringWithRange:[m rangeAtIndex:1]];if([src hasPrefix:@"https://"]&&![images containsObject:src])[images addObject:src];}
    NSString *summary=PlainHTML(html);if(summary.length>1600)summary=[[summary substringToIndex:1600] stringByAppendingString:@"…"];
    id published=[e[@"published"] isKindOfClass:NSDictionary.class]?e[@"published"][@"$t"]:nil;
    return @{@"title":title,@"summary":summary,@"published":[published isKindOfClass:NSString.class]?published:@"",@"url":url,@"images":images};
}
static NSString *FormatDate(NSDate *date){if(!date)return @"Sin datos";NSDateFormatter *f=[NSDateFormatter new];f.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"es_AR"];f.dateFormat=@"d MMM yyyy";return [f stringFromDate:date];}
static NSString *FormatBytes(NSNumber *size){return [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile];}
static NSArray *SaveSlots(void){
    NSString *data=[GameDirectory() stringByAppendingPathComponent:@"data/partidas"];NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:data error:nil]?:@[];NSMutableArray *slots=[NSMutableArray new];
    for(int i=1;i<=3;i++){NSString *prefix=[NSString stringWithFormat:@"reloaded%d.",i];BOOL used=NO;for(NSString *f in files)if([f.lowercaseString hasPrefix:prefix])used=YES;
        NSString *path=[data stringByAppendingPathComponent:[NSString stringWithFormat:@"reloaded%d.nfo",i]];NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]?:[NSString stringWithContentsOfFile:path encoding:NSWindowsCP1252StringEncoding error:nil];
        NSMutableArray *fields=[NSMutableArray new];for(NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSString *t=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(t.length)[fields addObject:t];}
        [slots addObject:@{@"index":@(i),@"used":@(used),@"name":fields.count>0?fields[0]:@"",@"seen":fields.count>1?fields[1]:@"",@"caught":fields.count>2?fields[2]:@"",@"place":fields.count>3?fields[3]:@""}];
    }return slots;
}

#import "Skin.h"

#import "NSDictionary+Types.h"
#import "NSArray+Blocks.h"
#import "NSArray+Access.h"
#import "NSDictionary+Intersection.h"
#import "UIColor+Hex.h"

static NSString *kSectionPathDelimiter = @".";
static NSString *kReferencePrefix = @"@";
static NSString *kHexPrefix = @"0x";

static NSString *kFontNameKey = @"name";
static NSString *kFontSizeKey = @"size";
static NSString *kSystemFont = @"systemfont";
static NSString *kBoldSystemFont = @"systemfont-bold";
static NSString *kItalicSystemFont = @"systemfont-italic";

static const CGFloat kDefaultFontSize = 14.0;

@interface Skin ()

@property (nonatomic, copy) NSString *section;
@property (nonatomic, retain) NSBundle *bundle;
@property (nonatomic, copy) NSDictionary *configuration;

@property (nonatomic, copy) NSCache *colors;
@property (nonatomic, copy) NSCache *images;
@property (nonatomic, copy) NSCache *fonts;

- (NSString *)valueForName:(NSString *)name inPart:(NSString *)section;

@end

#pragma mark - Helpers

static void with_skin_cache(void (^action) (NSMutableDictionary *cache))
{
  static dispatch_once_t initialized;
  static NSMutableDictionary *cache = nil;
  
  dispatch_once(&initialized, ^ {
		cache = [[NSMutableDictionary alloc] init];
  });
  
  action(cache);
}

static inline Skin *cached_skin_for_cache(NSString *section)
{
  __block Skin *result = nil;
  with_skin_cache(^(NSMutableDictionary *cache) {
    result = [cache objectForKey:section];
  });
  
  return result;
}

static inline void cache_skin(Skin *skin)
{
  with_skin_cache(^(NSMutableDictionary *cache) {
    [cache setObject:skin forKey:[skin section]];
  });
}

static Skin *skin_for_section(NSString *section)
{
  Skin *result = cached_skin_for_cache(section);

  if (nil == result)
  {
    result = [[[Skin alloc] initForSection:section] autorelease];
    cache_skin(result);
  }
  
  return result;
}

static inline NSString *path_for_section(NSString *section)
{
  return [NSString pathWithComponents:[section componentsSeparatedByString:kSectionPathDelimiter]];
}

static NSDictionary *merge_configurations(NSDictionary *parent, NSDictionary *child)
{
  __block NSMutableDictionary *configuration = [NSMutableDictionary dictionaryWithCapacity:7U];
  
  [[NSArray arrayWithObjects:@"images", @"colors", @"fonts", @"properties", nil] each:^(NSString *key) {
    NSDictionary *merged = [[parent objectForKey:key] merge:[child objectForKey:key]];
    [configuration setObject:merged forKey:key];
  }];
  
  return configuration;
}

static NSDictionary *resolve_references(NSDictionary *source)
{
  NSMutableDictionary *resolved = [NSMutableDictionary dictionaryWithCapacity:4];
  
  for (NSString *part_name in [NSArray arrayWithObjects:@"properties" ,@"images", @"fonts", @"colors", nil])
  {
    NSDictionary *part = [source objectForKey:part_name];
    NSMutableDictionary *resolved_part = [NSMutableDictionary dictionaryWithDictionary:part];
    
    NSSet *references = [part keysOfEntriesPassingTest:^ BOOL (id key, id obj, BOOL *stop) {
      return [obj isKindOfClass:[NSString class]] ? [obj hasPrefix:kReferencePrefix] : NO;
    }];
    
    for (NSString *key in references)
    {
      NSMutableSet *seen = [NSMutableSet set];
      
      NSString *value = [part objectForKey:key];
      do {
        [seen addObject:value];
        NSString *referenced_key = [value substringFromIndex:[kReferencePrefix length]];

          // KAO - TODO: probably should break this out and add a resolution strategy
        value = [part objectForKey:referenced_key];
        if (nil == value && ![@"properties" isEqualToString:part_name])
        {
          value = [resolved valueForKeyPath:[@"properties." stringByAppendingString:referenced_key]];
        }
        
        if ([value hasPrefix:kReferencePrefix] && [seen containsObject:value]) 
        {
          NSException *recursive = [NSException
                                    exceptionWithName:@"RecursiveReference"
                                    reason:[NSString stringWithFormat:@"Recursive reference found for key \"%@\"", key]
                                    userInfo:nil];
          @throw recursive;
        }
      } while ([value hasPrefix:kReferencePrefix]);
      
      [resolved_part setValue:value forKey:key];
    }
    
    [resolved setObject:resolved_part forKey:part_name];
  }
  
  return resolved;
}

static inline NSString *bundle_relative_path(NSString *full_path)
{
  NSUInteger min_length = [[[NSBundle mainBundle] resourcePath] length] + 1;
  
  return [full_path length] >= min_length ? [full_path substringFromIndex:min_length] : nil;
}

static inline NSString *value_for_name(NSDictionary *source, NSString *name, NSString *part)
{
  return [source valueForKeyPath:[[part stringByAppendingString: @"."] stringByAppendingString:name]];
}

#pragma mark - Skin

@implementation Skin

+ (Skin *)skin;
{
  return [self skinForSection:@""];
}

+ (Skin *)skinForSection:(NSString *)section;
{
  return skin_for_section(section);
}

@synthesize section = section_;
@synthesize bundle = bundle_;
@synthesize configuration = configuration_;

@synthesize colors = colors_;
@synthesize images = images_;
@synthesize fonts = fonts_;

- (id)initForSection:(NSString *)section;
{
  if ((self = [super init]))
  {
    section_ = [section copy];
    
    colors_ = [[NSCache alloc] init];
    images_ = [[NSCache alloc] init];
    fonts_ = [[NSCache alloc] init];
    
    NSString *skin_name = [[[NSBundle mainBundle] infoDictionary] stringForKey:@"skin-name" default:@"skin"];
    bundle_ = [[NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:skin_name ofType:@"bundle"]] retain];
    
    NSString *configuration_path = [bundle_ pathForResource:@"configuration" 
                                                     ofType:@"plist"
                                                inDirectory:path_for_section(section)];
    

    NSMutableDictionary *local_configuration = [NSMutableDictionary dictionaryWithContentsOfFile:configuration_path];
    for (NSString *part in [NSArray arrayWithObjects:@"images", @"colors", nil])
    {
      NSDictionary *part_configuration = [local_configuration objectForKey:part];
      NSMutableDictionary *expanded = [NSMutableDictionary dictionaryWithDictionary:part_configuration];
      [part_configuration enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([value isKindOfClass:[NSString class]] && !([value hasPrefix:kReferencePrefix] || [value hasPrefix:kHexPrefix]))
        {
          NSString *section_path = [path_for_section(section) stringByAppendingPathComponent:part];  
          NSString *resource_path = [bundle_ pathForResource:value ofType:nil inDirectory:section_path];
          NSString *path = bundle_relative_path(resource_path);
          
          [expanded setObject:path forKey:key];
        }
      }];
      
      [local_configuration setObject:expanded forKey:part];
    }
    
    NSDictionary *skin_configuration = nil;
    if ([section isEqualToString:@""])
    {
      skin_configuration = local_configuration;
    }
    else
    {
      NSArray *address = [section componentsSeparatedByString:kSectionPathDelimiter];
      NSString *parent_name = [[address trunk] componentsJoinedByString:kSectionPathDelimiter];
      Skin *parent = skin_for_section(parent_name);
            
      NSDictionary *parent_configuration = [parent configuration];
      
      skin_configuration = merge_configurations(parent_configuration, local_configuration);
    }
    
    configuration_ = [resolve_references(skin_configuration) copy];
  }
  
  return self;
}

- (void)dealloc;
{
  [colors_ release];
  [images_ release];
  [fonts_ release];
  
  [section_ release];
  [bundle_ release];
  [configuration_ release];
  
  [super dealloc];
}

#pragma mark - Fonts

- (UIFont *)fontNamed:(NSString *)name;
{
  UIFont *font = [[self fonts] objectForKey:name];
  
  if (nil == font)
  {
    NSString *font_name = nil;
    CGFloat font_size = kDefaultFontSize;
    
    id font_value = [self valueForName:name inPart:@"fonts"];
    
    if ([font_value isKindOfClass:[NSDictionary class]])
    {
      font_name = [font_value objectForKey:kFontNameKey];
      font_size = [[font_value objectForKey:kFontSizeKey] floatValue];
    }
    else
    {
      font_name = font_value;
    }
    
    if ([font_name isEqualToString:kSystemFont])
    {
      font = [UIFont systemFontOfSize:font_size];
    }
    else if ([font_name isEqualToString:kBoldSystemFont])
    {
      font = [UIFont boldSystemFontOfSize:font_size];
    }
    else if ([font_name isEqualToString:kItalicSystemFont])
    {
      font = [UIFont italicSystemFontOfSize:font_size];
    }
    else
    {
      font = [UIFont fontWithName:font_name size:font_size];
    }
    
    if (nil != font)
    {
      [[self fonts] setObject:font forKey:name];
    }
  }
  
  return font;
}

#pragma mark - Properties

- (id)propertyNamed:(NSString *)name;
{
  return [self valueForName:name inPart:@"properties"];
}       

#pragma mark - Colors

- (UIColor *)colorNamed:(NSString *)name;
{
  UIColor *color = [colors_ objectForKey:name];
  
  if (nil == color)
  {
    color = [UIColor cyanColor];

    NSString *value = [self valueForName:name inPart:@"colors"];
    if ([value hasPrefix:kHexPrefix])
    {
      color = [UIColor colorWithHexString:value];
    }
    else
    {
      UIImage *image = [UIImage imageNamed:value];
      if (nil != image)
      {
        color = [UIColor colorWithPatternImage:image];
      }
    }
    
    [colors_ setObject:color forKey:name];
  }

  return color;
}

#pragma mark - Images

- (void)withConfigurationAtPath:(NSString *)path do:(void (^) (id value))action
{
  id value = [[self configuration] valueForKeyPath:path];
  if (value)
  {
    action(value);
  }
}

- (UIImage *)imageNamed:(NSString *)name;
{
  NSParameterAssert(nil != name && [name length] > 0);
  
  UIImage *image = [images_ objectForKey:name];
  if (nil == image)
  {
    NSString *image_path = [self valueForName:name inPart:@"images"];
    image = [UIImage imageNamed:image_path];
    
    if (nil != image)
    {
      [images_ setObject:image forKey:name];
    }
  }
  
  return image;
}

#pragma mark - Utilities

- (NSString *)valueForName:(NSString *)name inPart:(NSString *)part;
{
  return value_for_name([self configuration], name, part);
}

@end
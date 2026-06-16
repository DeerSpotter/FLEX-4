#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

marker = 'FLEXingGlobalSearchPatchMarker'
if marker in text:
    print('Global FLEXing search patch already present')
    raise SystemExit(0)

text = text.replace(
    '@property (nonatomic, copy) NSString *kind;\n',
    '@property (nonatomic, copy) NSString *kind;\n@property (nonatomic, copy) NSString *searchText;\n'
)

text = text.replace(
    '    item.kind = kind ?: @"";\n    return item;\n',
    '    item.kind = kind ?: @"";\n    item.searchText = [NSString stringWithFormat:@"%@ %@ %@ %@", item.title ?: @"", item.subtitle ?: @"", item.section ?: @"", item.kind ?: @""].lowercaseString;\n    return item;\n'
)

text = text.replace(
    '            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@", item.title ?: @"", item.subtitle ?: @"", item.section ?: @"", item.kind ?: @""];\n            if ([haystack.lowercaseString containsString:lower]) {\n',
    '            NSString *haystack = item.searchText ?: @"";\n            if ([haystack containsString:lower]) {\n'
)

old = '''        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *className in classNames) {
            [items addObject:[FLEXingBrowserItem itemWithTitle:className subtitle:@"Obj-C Class" section:@"Obj-C Classes" kind:@"class"]];
        }
'''

new = '''        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSMutableArray<FLEXingBrowserItem *> *globalSearchItems = [NSMutableArray array];

        // FLEXingGlobalSearchPatchMarker: build one global index once, then filter strings only.
        NSDictionary *defaults = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        NSArray<NSString *> *defaultKeys = [defaults.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *key in defaultKeys) {
            id value = defaults[key];
            NSString *valueClass = value ? NSStringFromClass([value class]) : @"nil";
            NSString *displayType = valueClass.uppercaseString;
            if ([value isKindOfClass:NSNumber.class]) {
                NSString *objCType = [NSString stringWithUTF8String:[(NSNumber *)value objCType]];
                displayType = ([objCType containsString:@"B"] || [objCType containsString:@"c"]) ? @"BOOL" : @"NUMBER";
            } else if ([value isKindOfClass:NSString.class]) {
                displayType = @"STRING";
            } else if ([value isKindOfClass:NSArray.class]) {
                displayType = @"ARRAY";
            } else if ([value isKindOfClass:NSDictionary.class]) {
                displayType = @"DICTIONARY";
            }

            NSString *valueString = value ? [value description] : @"nil";
            if (valueString.length > 180) {
                valueString = [[valueString substringToIndex:180] stringByAppendingString:@"…"];
            }

            NSString *title = [NSString stringWithFormat:@"%@ %@", displayType, key];
            [globalSearchItems addObject:[FLEXingBrowserItem itemWithTitle:title subtitle:valueString section:@"Values / NSUserDefaults" kind:@"userDefault"]];
        }

        for (NSString *className in classNames) {
            @autoreleasepool {
                [items addObject:[FLEXingBrowserItem itemWithTitle:className subtitle:@"Obj-C Class" section:@"Obj-C Classes" kind:@"class"]];

                Class cls = NSClassFromString(className);
                if (!cls) {
                    continue;
                }

                unsigned int propertyCount = 0;
                objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
                for (unsigned int propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
                    const char *propertyName = property_getName(properties[propertyIndex]);
                    const char *attributes = property_getAttributes(properties[propertyIndex]);
                    if (!propertyName) {
                        continue;
                    }

                    NSString *name = [NSString stringWithUTF8String:propertyName];
                    NSString *attrs = attributes ? [NSString stringWithUTF8String:attributes] : @"";
                    NSString *title = [NSString stringWithFormat:@"PROPERTY %@", name];
                    NSString *subtitle = attrs.length ? [NSString stringWithFormat:@"%@ • %@", className, attrs] : className;
                    [globalSearchItems addObject:[FLEXingBrowserItem itemWithTitle:title subtitle:subtitle section:@"Properties" kind:@"property"]];
                }
                if (properties) {
                    free(properties);
                }

                unsigned int ivarCount = 0;
                Ivar *ivars = class_copyIvarList(cls, &ivarCount);
                for (unsigned int ivarIndex = 0; ivarIndex < ivarCount; ivarIndex++) {
                    const char *ivarName = ivar_getName(ivars[ivarIndex]);
                    const char *typeEncoding = ivar_getTypeEncoding(ivars[ivarIndex]);
                    if (!ivarName) {
                        continue;
                    }

                    NSString *name = [NSString stringWithUTF8String:ivarName];
                    NSString *type = typeEncoding ? [NSString stringWithUTF8String:typeEncoding] : @"";
                    NSString *title = [NSString stringWithFormat:@"IVAR %@", name];
                    NSString *subtitle = type.length ? [NSString stringWithFormat:@"%@ • %@", className, type] : className;
                    [globalSearchItems addObject:[FLEXingBrowserItem itemWithTitle:title subtitle:subtitle section:@"Ivars" kind:@"ivar"]];
                }
                if (ivars) {
                    free(ivars);
                }

                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(cls, &methodCount);
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    SEL selector = method_getName(methods[methodIndex]);
                    if (!selector) {
                        continue;
                    }

                    const char *typeEncoding = method_getTypeEncoding(methods[methodIndex]);
                    NSString *selectorName = NSStringFromSelector(selector);
                    NSString *encoding = typeEncoding ? [NSString stringWithUTF8String:typeEncoding] : @"";
                    NSString *title = [NSString stringWithFormat:@"- %@", selectorName];
                    NSString *subtitle = encoding.length ? [NSString stringWithFormat:@"%@ • %@", className, encoding] : className;
                    [globalSearchItems addObject:[FLEXingBrowserItem itemWithTitle:title subtitle:subtitle section:@"Obj-C Methods" kind:@"method"]];
                }
                if (methods) {
                    free(methods);
                }

                Class metaClass = object_getClass(cls);
                unsigned int classMethodCount = 0;
                Method *classMethods = class_copyMethodList(metaClass, &classMethodCount);
                for (unsigned int methodIndex = 0; methodIndex < classMethodCount; methodIndex++) {
                    SEL selector = method_getName(classMethods[methodIndex]);
                    if (!selector) {
                        continue;
                    }

                    const char *typeEncoding = method_getTypeEncoding(classMethods[methodIndex]);
                    NSString *selectorName = NSStringFromSelector(selector);
                    NSString *encoding = typeEncoding ? [NSString stringWithUTF8String:typeEncoding] : @"";
                    NSString *title = [NSString stringWithFormat:@"+ %@", selectorName];
                    NSString *subtitle = encoding.length ? [NSString stringWithFormat:@"%@ • %@", className, encoding] : className;
                    [globalSearchItems addObject:[FLEXingBrowserItem itemWithTitle:title subtitle:subtitle section:@"Obj-C Methods" kind:@"classMethod"]];
                }
                if (classMethods) {
                    free(classMethods);
                }
            }
        }

        [globalSearchItems sortUsingComparator:^NSComparisonResult(FLEXingBrowserItem *first, FLEXingBrowserItem *second) {
            NSComparisonResult sectionResult = [first.section localizedCaseInsensitiveCompare:second.section];
            if (sectionResult != NSOrderedSame) {
                return sectionResult;
            }
            NSComparisonResult titleResult = [first.title localizedCaseInsensitiveCompare:second.title];
            if (titleResult != NSOrderedSame) {
                return titleResult;
            }
            return [first.subtitle localizedCaseInsensitiveCompare:second.subtitle];
        }];
        [items addObjectsFromArray:globalSearchItems];
'''

if old not in text:
    raise SystemExit('Could not find baseline class-list block to patch')

path.write_text(text.replace(old, new))
print('Added global libraries/classes/properties/ivars/methods/defaults search index')

#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

marker = 'section:@"Setters / Values" kind:@"method"'
if marker in text:
    print('Setter/value search patch already present')
    raise SystemExit(0)

old = '''        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *className in classNames) {
            [items addObject:[FLEXingBrowserItem itemWithTitle:className subtitle:@"Obj-C Class" section:@"Obj-C Classes" kind:@"class"]];
        }
'''

new = '''        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSMutableArray<FLEXingBrowserItem *> *setterValueItems = [NSMutableArray array];
        for (NSString *className in classNames) {
            [items addObject:[FLEXingBrowserItem itemWithTitle:className subtitle:@"Obj-C Class" section:@"Obj-C Classes" kind:@"class"]];

            Class cls = NSClassFromString(className);
            if (!cls) {
                continue;
            }

            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                SEL selector = method_getName(methods[methodIndex]);
                if (!selector) {
                    continue;
                }

                NSString *selectorName = NSStringFromSelector(selector);
                NSString *lowerSelector = selectorName.lowercaseString;
                BOOL looksLikeSetterOrValue =
                    [selectorName hasPrefix:@"set"] ||
                    [lowerSelector containsString:@"value"] ||
                    [lowerSelector containsString:@"bool"] ||
                    [lowerSelector containsString:@"enabled"] ||
                    [lowerSelector containsString:@"hidden"] ||
                    [lowerSelector containsString:@"alpha"] ||
                    [lowerSelector containsString:@"frame"] ||
                    [lowerSelector containsString:@"text"];

                if (!looksLikeSetterOrValue) {
                    continue;
                }

                NSString *subtitle = [NSString stringWithFormat:@"%@ • instance method", className];
                [setterValueItems addObject:[FLEXingBrowserItem itemWithTitle:selectorName subtitle:subtitle section:@"Setters / Values" kind:@"method"]];
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

                NSString *selectorName = NSStringFromSelector(selector);
                NSString *lowerSelector = selectorName.lowercaseString;
                BOOL looksLikeSetterOrValue =
                    [selectorName hasPrefix:@"set"] ||
                    [lowerSelector containsString:@"value"] ||
                    [lowerSelector containsString:@"bool"] ||
                    [lowerSelector containsString:@"enabled"] ||
                    [lowerSelector containsString:@"hidden"] ||
                    [lowerSelector containsString:@"alpha"] ||
                    [lowerSelector containsString:@"frame"] ||
                    [lowerSelector containsString:@"text"];

                if (!looksLikeSetterOrValue) {
                    continue;
                }

                NSString *subtitle = [NSString stringWithFormat:@"%@ • class method", className];
                [setterValueItems addObject:[FLEXingBrowserItem itemWithTitle:selectorName subtitle:subtitle section:@"Setters / Values" kind:@"method"]];
            }
            if (classMethods) {
                free(classMethods);
            }
        }

        [setterValueItems sortUsingComparator:^NSComparisonResult(FLEXingBrowserItem *first, FLEXingBrowserItem *second) {
            NSComparisonResult titleResult = [first.title localizedCaseInsensitiveCompare:second.title];
            if (titleResult != NSOrderedSame) {
                return titleResult;
            }
            return [first.subtitle localizedCaseInsensitiveCompare:second.subtitle];
        }];
        [items addObjectsFromArray:setterValueItems];
'''

if old not in text:
    raise SystemExit('Could not find baseline class-list block to patch')

path.write_text(text.replace(old, new))
print('Added setter/value methods to FLEXing search results')

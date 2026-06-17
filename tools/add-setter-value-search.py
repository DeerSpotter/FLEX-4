#!/usr/bin/env python3
from pathlib import Path

path = Path('Tweak.xm')
text = path.read_text()

marker = 'FLEXingFastVisualGlobalSearchPatchMarker'
if marker in text:
    print('Fast visual global search patch already present')
    raise SystemExit(0)

def patch(old, new, label):
    global text
    if old not in text:
        raise SystemExit(f'Could not find block to patch: {label}')
    text = text.replace(old, new, 1)

patch('@property (nonatomic, copy) NSString *kind;\n', '@property (nonatomic, copy) NSString *kind;\n@property (nonatomic, copy) NSString *searchText;\n', 'item searchText property')

patch('    item.kind = kind ?: @"";\n    return item;\n', '    item.kind = kind ?: @"";\n    item.searchText = [NSString stringWithFormat:@"%@ %@ %@ %@", item.title ?: @"", item.subtitle ?: @"", item.section ?: @"", item.kind ?: @""].lowercaseString;\n    return item;\n', 'item searchText assignment')

patch('@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *allItems;\n@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *filteredItems;\n@property (nonatomic, copy) NSString *query;\n', '@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *allItems;\n@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *filteredItems;\n@property (nonatomic, strong) NSArray<FLEXingBrowserItem *> *asyncGlobalItems;\n@property (nonatomic, copy) NSString *query;\n@property (nonatomic, assign) NSUInteger asyncSearchGeneration;\n', 'async search properties')

patch('        self.query = @"";\n', '        self.query = @"";\n        self.asyncGlobalItems = @[];\n', 'async array init')

patch('    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"FLEXingCell"];\n', f'    // {marker}: use subtitle cells like FLEX native panels.\n', 'cell registration')

old_apply = '''- (void)applyFilter {
    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.filteredItems = self.allItems;
    } else {
        NSString *lower = trimmed.lowercaseString;
        NSMutableArray<FLEXingBrowserItem *> *matches = [NSMutableArray array];
        for (FLEXingBrowserItem *item in self.allItems) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@", item.title ?: @"", item.subtitle ?: @"", item.section ?: @"", item.kind ?: @""];
            if ([haystack.lowercaseString containsString:lower]) {
                [matches addObject:item];
            }
        }
        self.filteredItems = matches;
    }
    [self.tableView reloadData];
}
'''
new_apply = '''- (void)applyFilter {
    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.filteredItems = self.allItems;
    } else {
        NSString *lower = trimmed.lowercaseString;
        NSMutableArray<FLEXingBrowserItem *> *matches = [NSMutableArray array];
        NSUInteger displayLimit = 700;

        for (FLEXingBrowserItem *item in self.allItems) {
            if ([(item.searchText ?: @"") containsString:lower]) {
                [matches addObject:item];
                if (matches.count >= displayLimit) { break; }
            }
        }

        if (matches.count < displayLimit) {
            for (FLEXingBrowserItem *item in self.asyncGlobalItems ?: @[]) {
                if ([(item.searchText ?: @"") containsString:lower]) {
                    [matches addObject:item];
                    if (matches.count >= displayLimit) { break; }
                }
            }
        }

        self.filteredItems = matches;
    }
    [self.tableView reloadData];
}
'''
patch(old_apply, new_apply, 'fast applyFilter')

old_cell = '''- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FLEXingCell" forIndexPath:indexPath];
    FLEXingBrowserItem *item = [self itemsForSection:indexPath.section][(NSUInteger)indexPath.row];

    cell.textLabel.text = item.title;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = ([item.kind isEqualToString:@"toggleEnabled"] || [item.kind isEqualToString:@"toggleAutoShow"] || [item.kind isEqualToString:@"editAdjustments"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    if (item.subtitle.length > 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@\n%@", item.title, item.subtitle];
    }

    return cell;
}
'''
new_cell = '''- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FLEXingCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FLEXingCell"];
    }

    FLEXingBrowserItem *item = [self itemsForSection:indexPath.section][(NSUInteger)indexPath.row];

    cell.textLabel.text = item.title;
    cell.detailTextLabel.text = item.subtitle;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.accessoryType = ([item.kind isEqualToString:@"toggleEnabled"] || [item.kind isEqualToString:@"toggleAutoShow"] || [item.kind isEqualToString:@"editAdjustments"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    BOOL runtimeRow = [item.kind isEqualToString:@"method"] || [item.kind isEqualToString:@"classMethod"] || [item.kind isEqualToString:@"property"] || [item.kind isEqualToString:@"ivar"] || [item.kind isEqualToString:@"userDefault"];
    if (runtimeRow) {
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    } else {
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    }

    return cell;
}
'''
patch(old_cell, new_cell, 'FLEX visual cell style')

old_search = '''- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}
'''
new_search = '''- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    self.asyncSearchGeneration++;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flexingRunDeferredGlobalSearch) object:nil];

    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.asyncGlobalItems = @[];
    } else {
        [self performSelector:@selector(flexingRunDeferredGlobalSearch) withObject:nil afterDelay:0.20];
    }

    [self applyFilter];
}

- (void)flexingRunDeferredGlobalSearch {
    NSString *trimmed = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        self.asyncGlobalItems = @[];
        [self applyFilter];
        return;
    }

    NSUInteger generation = self.asyncSearchGeneration;
    NSString *lower = trimmed.lowercaseString;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSMutableArray<FLEXingBrowserItem *> *matches = [NSMutableArray array];
            NSUInteger limit = 700;

            void (^addIfMatch)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *title, NSString *subtitle, NSString *section, NSString *kind) {
                if (matches.count >= limit) { return; }
                NSString *searchText = [NSString stringWithFormat:@"%@ %@ %@ %@", title ?: @"", subtitle ?: @"", section ?: @"", kind ?: @""].lowercaseString;
                if ([searchText containsString:lower]) {
                    [matches addObject:[FLEXingBrowserItem itemWithTitle:title subtitle:subtitle section:section kind:kind]];
                }
            };

            NSDictionary *defaults = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
            for (NSString *key in [defaults.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
                if (matches.count >= limit) { break; }
                id value = defaults[key];
                NSString *displayType = value ? NSStringFromClass([value class]).uppercaseString : @"NIL";
                if ([value isKindOfClass:NSNumber.class]) {
                    const char *objCType = [(NSNumber *)value objCType];
                    NSString *type = objCType ? [NSString stringWithUTF8String:objCType] : @"";
                    displayType = ([type containsString:@"B"] || [type containsString:@"c"]) ? @"BOOL" : @"NUMBER";
                } else if ([value isKindOfClass:NSString.class]) {
                    displayType = @"STRING";
                } else if ([value isKindOfClass:NSArray.class]) {
                    displayType = @"ARRAY";
                } else if ([value isKindOfClass:NSDictionary.class]) {
                    displayType = @"DICTIONARY";
                }
                NSString *valueString = value ? [value description] : @"nil";
                if (valueString.length > 140) { valueString = [[valueString substringToIndex:140] stringByAppendingString:@"…"]; }
                addIfMatch([NSString stringWithFormat:@"%@ %@", displayType, key], valueString, @"Values / NSUserDefaults", @"userDefault");
            }

            int classCount = objc_getClassList(NULL, 0);
            if (classCount > 0 && matches.count < limit) {
                Class *classes = (Class *)calloc((NSUInteger)classCount, sizeof(Class));
                int actualCount = objc_getClassList(classes, classCount);
                for (int classIndex = 0; classIndex < actualCount && matches.count < limit; classIndex++) {
                    Class cls = classes[classIndex];
                    const char *classNameC = class_getName(cls);
                    if (!classNameC) { continue; }
                    NSString *className = [NSString stringWithUTF8String:classNameC];

                    unsigned int propertyCount = 0;
                    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
                    for (unsigned int i = 0; i < propertyCount && matches.count < limit; i++) {
                        const char *propertyName = property_getName(properties[i]);
                        const char *attributes = property_getAttributes(properties[i]);
                        if (!propertyName) { continue; }
                        NSString *name = [NSString stringWithUTF8String:propertyName];
                        NSString *attrs = attributes ? [NSString stringWithUTF8String:attributes] : @"";
                        addIfMatch(name, attrs.length ? [NSString stringWithFormat:@"%@ • %@", className, attrs] : className, @"Properties", @"property");
                    }
                    if (properties) { free(properties); }

                    unsigned int methodCount = 0;
                    Method *methods = class_copyMethodList(cls, &methodCount);
                    for (unsigned int i = 0; i < methodCount && matches.count < limit; i++) {
                        SEL selector = method_getName(methods[i]);
                        if (!selector) { continue; }
                        const char *typeEncoding = method_getTypeEncoding(methods[i]);
                        NSString *selectorName = NSStringFromSelector(selector);
                        NSString *encoding = typeEncoding ? [NSString stringWithUTF8String:typeEncoding] : @"";
                        addIfMatch([NSString stringWithFormat:@"- %@", selectorName], encoding.length ? [NSString stringWithFormat:@"%@ • %@", className, encoding] : className, @"Obj-C Methods", @"method");
                    }
                    if (methods) { free(methods); }
                }
                free(classes);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.asyncSearchGeneration) { return; }
                self.asyncGlobalItems = matches;
                [self applyFilter];
            });
        }
    });
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}
'''
patch(old_search, new_search, 'debounced async global search')

path.write_text(text)
print('Added FLEX-style visual cells and fast debounced global search')

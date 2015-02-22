#import "FORMCollectionViewDataSource.h"

#import "FORMBackgroundView.h"
#import "FORMCollectionViewLayout.h"

#import "FORMTextFieldCell.h"
#import "FORMSelectFieldCell.h"
#import "FORMDateFieldCell.h"
#import "FORMButtonFieldCell.h"
#import "FORMFieldValue.h"

#import "UIColor+ANDYHex.h"
#import "UIScreen+HYPLiveBounds.h"
#import "NSString+HYPWordExtractor.h"
#import "NSString+HYPFormula.h"
#import "UIDevice+HYPRealOrientation.h"
#import "NSObject+HYPTesting.h"

static const CGFloat FORMDispatchTime = 0.05f;

@interface FORMCollectionViewDataSource () <FORMBaseFieldCellDelegate, FORMHeaderViewDelegate>

@property (nonatomic) UIEdgeInsets originalInset;
@property (nonatomic) BOOL disabled;
@property (nonatomic, strong, readwrite) FORMData *formsManager;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) FORMCollectionViewLayout *layout;
@property (nonatomic, copy) NSArray *JSON;

@end

@implementation FORMCollectionViewDataSource

#pragma mark - Dealloc

- (void)dealloc
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIKeyboardDidShowNotification object:nil];
    [center removeObserver:self name:UIKeyboardDidHideNotification object:nil];
}

#pragma mark - Initializers

- (instancetype)initWithJSON:(NSArray *)JSON
              collectionView:(UICollectionView *)collectionView
                      layout:(FORMCollectionViewLayout *)layout
                      values:(NSDictionary *)values
                    disabled:(BOOL)disabled
{
    self = [super init];
    if (!self) return nil;

    _collectionView = collectionView;

    _layout = layout;

    _originalInset = collectionView.contentInset;

    layout.dataSource = self;

    _formsManager = [[FORMData alloc] initWithJSON:JSON
                                            initialValues:values
                                         disabledFieldIDs:@[]
                                                 disabled:disabled];

    [collectionView registerClass:[FORMTextFieldCell class]
       forCellWithReuseIdentifier:FORMTextFieldCellIdentifier];

    [collectionView registerClass:[FORMSelectFieldCell class]
       forCellWithReuseIdentifier:HYPSelectFormFieldCellIdentifier];

    [collectionView registerClass:[FORMDateFieldCell class]
       forCellWithReuseIdentifier:HYPDateFormFieldCellIdentifier];

    [collectionView registerClass:[FORMButtonFieldCell class]
       forCellWithReuseIdentifier:FORMButtonFieldCellIdentifier];

    [collectionView registerClass:[FORMGroupHeaderView class]
       forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
              withReuseIdentifier:FORMHeaderReuseIdentifier];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];

    return self;
}

#pragma mark - Getters

- (NSMutableArray *)collapsedForms
{
    if (_collapsedForms) return _collapsedForms;

    _collapsedForms = [NSMutableArray new];

    return _collapsedForms;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return self.formsManager.forms.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    FORMGroup *form = self.formsManager.forms[section];
    if ([self.collapsedForms containsObject:@(section)]) {
        return 0;
    }

    return [form numberOfFields:self.formsManager.hiddenSections];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    FORMGroup *form = self.formsManager.forms[indexPath.section];
    NSArray *fields = form.fields;
    FORMField *field = fields[indexPath.row];

    if (self.configureCellForIndexPath) {
        id configuredCell = self.configureCellForIndexPath(field, collectionView, indexPath);
        if (configuredCell) return configuredCell;
    }

    NSString *identifier;

    switch (field.type) {
        case FORMFieldTypeDate:
            identifier = HYPDateFormFieldCellIdentifier;
            break;
        case FORMFieldTypeSelect:
            identifier = HYPSelectFormFieldCellIdentifier;
            break;

        case FORMFieldTypeText:
        case FORMFieldTypeFloat:
        case FORMFieldTypeNumber:
            identifier = FORMTextFieldCellIdentifier;
            break;

        case FORMFieldTypeButton:
            identifier = FORMButtonFieldCellIdentifier;
            break;

        case FORMFieldTypeCustom: abort();
    }

    FORMBaseFieldCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:identifier
                                                                           forIndexPath:indexPath];
    cell.delegate = self;

    if (self.configureCellBlock) {
        self.configureCellBlock(cell, indexPath, field);
    } else {
        cell.field = field;
    }

    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath
{
    if (kind == UICollectionElementKindSectionHeader) {
        FORMGroupHeaderView *headerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                           withReuseIdentifier:FORMHeaderReuseIdentifier
                                                                                  forIndexPath:indexPath];

        FORMGroup *form = self.formsManager.forms[indexPath.section];
        headerView.section = indexPath.section;

        if (self.configureHeaderViewBlock) {
            self.configureHeaderViewBlock(headerView, kind, indexPath, form);
        } else {
            headerView.headerLabel.text = form.title;
            headerView.delegate = self;
        }

        return headerView;
    }

    return nil;
}

#pragma mark - Public methods

- (void)collapseFieldsInSection:(NSInteger)section collectionView:(UICollectionView *)collectionView
{
    BOOL headerIsCollapsed = ([self.collapsedForms containsObject:@(section)]);

    NSMutableArray *indexPaths = [NSMutableArray new];
    FORMGroup *form = self.formsManager.forms[section];

    for (NSInteger i = 0; i < form.fields.count; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:section];
        [indexPaths addObject:indexPath];
    }

    if (headerIsCollapsed) {
        [self.collapsedForms removeObject:@(section)];
        [collectionView insertItemsAtIndexPaths:indexPaths];
        [collectionView.collectionViewLayout invalidateLayout];
    } else {
        [self.collapsedForms addObject:@(section)];
        [collectionView deleteItemsAtIndexPaths:indexPaths];
        [collectionView.collectionViewLayout invalidateLayout];
    }
}

- (NSArray *)safeIndexPaths:(NSArray *)indexPaths
{
    NSMutableArray *safeIndexPaths = [NSMutableArray new];

    for (NSIndexPath *indexPath in indexPaths) {
        if (![self.collapsedForms containsObject:@(indexPath.section)]) {
            [safeIndexPaths addObject:indexPath];
        }
    }

    return safeIndexPaths;
}

- (void)insertItemsAtIndexPaths:(NSArray *)indexPaths
{
    NSArray *reloadedIndexPaths = [self safeIndexPaths:indexPaths];

    if (reloadedIndexPaths.count > 0) {
        [self.collectionView performBatchUpdates:^{
            [self.collectionView insertItemsAtIndexPaths:reloadedIndexPaths];
        } completion:^(BOOL finished) {
            if (finished) [self.collectionView reloadData];
        }];
    }
}

- (void)deleteItemsAtIndexPaths:(NSArray *)indexPaths
{
    NSArray *reloadedIndexPaths = [self safeIndexPaths:indexPaths];

    if (reloadedIndexPaths.count > 0) {
        [self.collectionView deleteItemsAtIndexPaths:reloadedIndexPaths];
    }
}

- (void)reloadItemsAtIndexPaths:(NSArray *)indexPaths
{
    NSArray *reloadedIndexPaths = [self safeIndexPaths:indexPaths];

    if (reloadedIndexPaths.count > 0) {
        [UIView performWithoutAnimation:^{
            [self.collectionView reloadItemsAtIndexPaths:reloadedIndexPaths];
        }];
    }
}

- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    FORMGroup *form = self.formsManager.forms[indexPath.section];

    NSArray *fields = form.fields;

    CGRect bounds = [[UIScreen mainScreen] hyp_liveBounds];
    CGFloat deviceWidth = CGRectGetWidth(bounds) - (FORMMarginHorizontal * 2);
    CGFloat width = 0.0f;
    CGFloat height = 0.0f;

    FORMField *field;
    if (indexPath.row < fields.count) {
        field = fields[indexPath.row];
    }
    if (field.sectionSeparator) {
        width = deviceWidth;
        height = FORMFieldCellItemSmallHeight;
    } else if (field) {
        width = floor(deviceWidth * (field.size.width / 100.0f));

        if (field.type == FORMFieldTypeCustom) {
            height = field.size.height * FORMFieldCellItemHeight;
        } else {
            height = FORMFieldCellItemHeight;
        }
    }

    return CGSizeMake(width, height);
}

- (FORMField *)formFieldAtIndexPath:(NSIndexPath *)indexPath
{
    FORMGroup *form = self.formsManager.forms[indexPath.section];
    NSArray *fields = form.fields;
    FORMField *field = fields[indexPath.row];

    return field;
}

- (void)enable
{
    [self disable:NO];
}

- (void)disable
{
    [self disable:YES];
}

- (void)disable:(BOOL)disabled
{
    self.disabled = disabled;

    if (disabled) {
        [self.formsManager disable];
    } else {
        [self.formsManager enable];
    }

    NSMutableDictionary *fields = [NSMutableDictionary new];

    for (FORMGroup *form in self.formsManager.forms) {
        for (FORMField *field in form.fields) {
            if (field.fieldID) [fields addEntriesFromDictionary:@{field.fieldID : field}];
        }
    }

    [fields addEntriesFromDictionary:self.formsManager.hiddenFieldsAndFieldIDsDictionary];

    for (FORMSection *section in [self.formsManager.hiddenSections allValues]) {
        for (FORMField *field in section.fields) {
            if (field.fieldID) [fields addEntriesFromDictionary:@{field.fieldID : field}];
        }
    }

    for (NSString *fieldID in fields) {
        FORMField *field = [fields valueForKey:fieldID];
        BOOL shouldChangeState = (![self.formsManager.disabledFieldsIDs containsObject:fieldID]);

        if (disabled) {
            field.disabled = YES;
        } else if (shouldChangeState) {
            if (!field.initiallyDisabled) field.disabled = NO;

            if (field.targets.count > 0) {
                [self processTargets:field.targets];
            } else if (field.type == FORMFieldTypeSelect) {
                BOOL hasFieldValue = (field.fieldValue && [field.fieldValue isKindOfClass:[FORMFieldValue class]]);
                if (hasFieldValue) {
                    FORMFieldValue *fieldValue = (FORMFieldValue *)field.fieldValue;

                    NSMutableArray *targets = [NSMutableArray new];

                    for (FORMTarget *target in fieldValue.targets) {
                        BOOL targetIsNotEnableOrDisable = (target.actionType != FORMTargetActionEnable &&
                                                           target.actionType != FORMTargetActionDisable);
                        if (targetIsNotEnableOrDisable) [targets addObject:target];
                    }

                    if (targets.count > 0) [self processTargets:targets];
                }
            }
        }
    }

    [UIView performWithoutAnimation:^{
        [self.collectionView reloadItemsAtIndexPaths:[self.collectionView indexPathsForVisibleItems]];
    }];
}

- (BOOL)isDisabled
{
    return self.disabled;
}

- (BOOL)isEnabled
{
    return !self.disabled;
}

- (void)reloadWithDictionary:(NSDictionary *)dictionary
{
    [self.formsManager.values setValuesForKeysWithDictionary:dictionary];

    NSMutableArray *updatedIndexPaths = [NSMutableArray new];
    NSMutableArray *targets = [NSMutableArray new];

    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        [self.formsManager fieldWithID:key includingHiddenFields:YES completion:^(FORMField *field, NSIndexPath *indexPath) {
            BOOL shouldBeNil = ([value isEqual:[NSNull null]]);

            if (field) {
                field.fieldValue = (shouldBeNil) ? nil : value;
                if (indexPath) [updatedIndexPaths addObject:indexPath];
                [targets addObjectsFromArray:[field safeTargets]];
            } else {
                field = ([self fieldInDeletedFields:key]) ?: [self fieldInDeletedSections:key];
                if (field) field.fieldValue = (shouldBeNil) ? nil : value;
            }
        }];
    }];

    [self processTargets:targets];
}

- (FORMField *)fieldInDeletedFields:(NSString *)fieldID
{
    __block FORMField *foundField = nil;

    [self.formsManager.hiddenFieldsAndFieldIDsDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, FORMField *field, BOOL *stop) {
        if ([field.fieldID isEqualToString:fieldID]) {
            foundField = field;
            *stop = YES;
        }
    }];

    return foundField;
}

- (FORMField *)fieldInDeletedSections:(NSString *)fieldID
{
    __block FORMField *foundField = nil;

    [self.formsManager.hiddenSections enumerateKeysAndObjectsUsingBlock:^(NSString *key, FORMSection *section, BOOL *stop) {
        [section.fields enumerateObjectsUsingBlock:^(FORMField *field, NSUInteger idx, BOOL *stop) {
            if ([field.fieldID isEqualToString:fieldID]) {
                foundField = field;
                *stop = YES;
            }
        }];
    }];

    return foundField;
}

#pragma mark Validations

- (void)validateForms
{
    NSMutableSet *validatedFields = [NSMutableSet set];

    NSArray *cells = [self.collectionView visibleCells];
    for (FORMBaseFieldCell *cell in cells) {
        if ([cell respondsToSelector:@selector(validate)]) {
            [cell validate];

            if (cell.field.fieldID) {
                [validatedFields addObject:cell.field.fieldID];
            }
        }
    }

    for (FORMGroup *form in self.formsManager.forms) {
        for (FORMField *field in form.fields) {
            if (![validatedFields containsObject:field.fieldID]) {
                [field validate];
            }
        }
    }
}

- (BOOL)formFieldsAreValid
{
    for (FORMGroup *form in self.formsManager.forms) {
        for (FORMField *field in form.fields) {
            FORMValidationResultType fieldValidation = [field validate];
            BOOL requiredFieldFailedValidation = (fieldValidation != FORMValidationResultTypePassed);
            if (requiredFieldFailedValidation) {
                return NO;
            }
        }
    }

    return YES;
}

- (void)resetForms
{
    self.formsManager = nil;
    [self.collapsedForms removeAllObjects];
    [self.formsManager.hiddenFieldsAndFieldIDsDictionary removeAllObjects];
    [self.formsManager.hiddenSections removeAllObjects];
    [self.collectionView reloadData];
}

#pragma mark - FORMBaseFieldCellDelegate

- (void)fieldCell:(UICollectionViewCell *)fieldCell updatedWithField:(FORMField *)field
{
    if (self.configureFieldUpdatedBlock) {
        self.configureFieldUpdatedBlock(fieldCell, field);
    }

    if (!field.fieldValue) {
        [self.formsManager.values removeObjectForKey:field.fieldID];
    } else if ([field.fieldValue isKindOfClass:[FORMFieldValue class]]) {
        FORMFieldValue *fieldValue = field.fieldValue;
        self.formsManager.values[field.fieldID] = fieldValue.valueID;
    } else {
        self.formsManager.values[field.fieldID] = field.fieldValue;
    }

    if (field.fieldValue && [field.fieldValue isKindOfClass:[FORMFieldValue class]]) {
        FORMFieldValue *fieldValue = field.fieldValue;
        [self processTargets:fieldValue.targets];
    } else if (field.targets.count > 0) {
        [self processTargets:field.targets];
    }
}

- (void)fieldCell:(UICollectionViewCell *)fieldCell processTargets:(NSArray *)targets
{
    NSTimeInterval delay = ([NSObject isUnitTesting]) ? FORMDispatchTime : 0.0f;
    [self performSelector:@selector(processTargets:) withObject:targets afterDelay:delay];
}

#pragma mark - Targets Procesing

- (void)processTarget:(FORMTarget *)target
{
    switch (target.actionType) {
        case FORMTargetActionShow: {
            NSArray *insertedIndexPaths = [self.formsManager showTargets:@[target]];
            [self insertItemsAtIndexPaths:insertedIndexPaths];
        } break;
        case FORMTargetActionHide: {
            NSArray *deletedIndexPaths = [self.formsManager hideTargets:@[target]];
            [self deleteItemsAtIndexPaths:deletedIndexPaths];
        } break;
        case FORMTargetActionClear:
        case FORMTargetActionUpdate: {
            NSArray *updatedIndexPaths = [self.formsManager updateTargets:@[target]];
            [self reloadItemsAtIndexPaths:updatedIndexPaths];
        } break;
        case FORMTargetActionEnable: {
            if ([self.formsManager isEnabled]) {
                NSArray *enabledIndexPaths = [self.formsManager enableTargets:@[target]];
                [self reloadItemsAtIndexPaths:enabledIndexPaths];
            }
        } break;
        case FORMTargetActionDisable: {
            NSArray *disabledIndexPaths = [self.formsManager disableTargets:@[target]];
            [self reloadItemsAtIndexPaths:disabledIndexPaths];
        } break;
        case FORMTargetActionNone: break;
    }
}

- (NSArray *)sortTargets:(NSArray *)targets
{
    NSSortDescriptor *sortByTypeString = [NSSortDescriptor sortDescriptorWithKey:@"typeString" ascending:YES];
    NSArray *sortedTargets = [targets sortedArrayUsingDescriptors:@[sortByTypeString]];

    return sortedTargets;
}

- (void)processTargets:(NSArray *)targets
{
    [FORMTarget filteredTargets:targets
                          filtered:^(NSArray *shownTargets,
                                     NSArray *hiddenTargets,
                                     NSArray *updatedTargets,
                                     NSArray *enabledTargets,
                                     NSArray *disabledTargets) {
                              shownTargets  = [self sortTargets:shownTargets];
                              hiddenTargets = [self sortTargets:hiddenTargets];

                              NSArray *insertedIndexPaths;
                              NSArray *deletedIndexPaths;
                              NSArray *updatedIndexPaths;
                              NSArray *enabledIndexPaths;
                              NSArray *disabledIndexPaths;

                              if (shownTargets.count > 0) {
                                  insertedIndexPaths = [self.formsManager showTargets:shownTargets];
                                  [self insertItemsAtIndexPaths:insertedIndexPaths];
                              }

                              if (hiddenTargets.count > 0) {
                                  deletedIndexPaths = [self.formsManager hideTargets:hiddenTargets];
                                  [self deleteItemsAtIndexPaths:deletedIndexPaths];
                              }

                              if (updatedTargets.count > 0) {
                                  updatedIndexPaths = [self.formsManager updateTargets:updatedTargets];

                                  if (deletedIndexPaths) {
                                      NSMutableArray *filteredIndexPaths = [updatedIndexPaths mutableCopy];
                                      for (NSIndexPath *indexPath in updatedIndexPaths) {
                                          if ([deletedIndexPaths containsObject:indexPath]) {
                                              [filteredIndexPaths removeObject:indexPath];
                                          }
                                      }

                                      [self reloadItemsAtIndexPaths:filteredIndexPaths];
                                  } else {
                                      [self reloadItemsAtIndexPaths:updatedIndexPaths];
                                  }
                              }

                              BOOL shouldRunEnableTargets = (enabledTargets.count > 0 && [self.formsManager isEnabled]);
                              if (shouldRunEnableTargets) {
                                  enabledIndexPaths = [self.formsManager enableTargets:enabledTargets];

                                  [self reloadItemsAtIndexPaths:enabledIndexPaths];
                              }

                              if (disabledTargets.count > 0) {
                                  disabledIndexPaths = [self.formsManager disableTargets:disabledTargets];

                                  [self reloadItemsAtIndexPaths:disabledIndexPaths];
                              }
                          }];
}

#pragma mark - Target helpers

#pragma mark Sections

- (void)insertedIndexPathsAndSectionIndexForSection:(FORMSection *)section
                                         completion:(void (^)(NSArray *indexPaths, NSInteger index))completion
{
    NSMutableArray *indexPaths = [NSMutableArray new];

    NSInteger formIndex = [section.form.position integerValue];
    FORMGroup *form = self.formsManager.forms[formIndex];

    NSInteger fieldsIndex = 0;
    NSInteger sectionIndex = 0;
    for (FORMSection *aSection in form.sections) {
        if ([aSection.position integerValue] < [section.position integerValue]) {
            fieldsIndex += aSection.fields.count;
            sectionIndex++;
        }
    }

    NSInteger fieldsInSectionCount = fieldsIndex + section.fields.count;
    for (NSInteger i = fieldsIndex; i < fieldsInSectionCount; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:formIndex]];
    }

    if (completion) {
        completion(indexPaths, sectionIndex);
    }
}

#pragma mark - Keyboard Support

- (void)keyboardDidShow:(NSNotification *)notification
{
    CGRect keyboardEndFrame;
    [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] getValue:&keyboardEndFrame];

    NSInteger height = CGRectGetHeight(keyboardEndFrame);
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 8.0) {
        if ([[UIDevice currentDevice] hyp_isLandscape]) {
            height = CGRectGetWidth(keyboardEndFrame);
        }
    }

    UIEdgeInsets inset = self.originalInset;
    inset.bottom += height;

    [UIView animateWithDuration:0.3f animations:^{
        self.collectionView.contentInset = inset;
    }];
}

- (void)keyboardDidHide:(NSNotification *)notification
{
    CGRect keyboardEndFrame;
    [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] getValue:&keyboardEndFrame];

    [UIView animateWithDuration:0.3f animations:^{
        self.collectionView.contentInset = self.originalInset;
    }];
}

#pragma mark - FORMHeaderViewDelegate

- (void)formHeaderViewWasPressed:(FORMGroupHeaderView *)headerView
{
    [self collapseFieldsInSection:headerView.section collectionView:self.collectionView];
}

#pragma mark - HYPFormsLayoutDataSource

- (NSArray *)forms
{
    return self.formsManager.forms;
}

@end

//
//  REMAFormatter.h
//  Mine Ansatte
//
//  Created by Christoffer Winterkvist on 9/23/14.
//  Copyright (c) 2014 Hyper. All rights reserved.
//

#import "REMAFormField.h"

@interface REMAFormatter : NSObject

+ (Class)formatterClass:(NSString *)string;
- (NSString *)formatString:(NSString *)string reverse:(BOOL)reverse;

@end
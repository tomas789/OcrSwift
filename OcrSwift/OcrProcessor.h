//
//  OcrProcessor.h
//  OcrSwift
//
//  Created by Tomas Krejci on 1/6/17.
//  Copyright © 2017 Tomas Krejci. All rights reserved.
//

#ifndef OcrProcessor_h
#define OcrProcessor_h

#import <UIKit/UIKit.h>

struct CppMembers;

@interface OcrProcessor : NSObject {
    struct CppMembers *_cpp;
}

@property UIImage *licensePlatePatch;
@property float statisticConfidence;

- (UIImage*) process: (UIImage*)image withRotation:(double)rotation;
- (NSString*) statisticProcessor: (NSString*)recognized;

@end

#endif /* OcrProcessor_h */

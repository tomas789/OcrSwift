//
//  OcrProcessor.m
//  OcrSwift
//
//  Created by Tomas Krejci on 1/6/17.
//  Copyright © 2017 Tomas Krejci. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OcrProcessor.h"
#import <opencv2/core/core.hpp>
#import <opencv2/imgproc/imgproc.hpp>
#import <iostream>
#import <vector>
#import <algorithm>
#import <numeric>
#import <map>

struct RecognizedCharacter {
    char character;
    float confidence;
    int width;
    int height;
    int position;
};

struct CppMembers {
    double plateToImageWidthRatio = 0.7;
    int markerLen = 32;
    int markerLineWidth = 3;
    cv::Scalar contourColor = cv::Scalar(255, 0, 0);
    cv::Scalar rectangleColor = cv::Scalar(0, 255, 0);
    float symbolWidthToHeightRatio = 221.0/387.0;
    float plateWidthToHeightRatio = 970.0/209.0;
    float symbolToPlateAreaRatio = (221.0*387.0)/(2780.0*607.0);

    static const int statisticSize = 20;
    std::size_t begin = 0;
    std::size_t end = 0;
    std::vector<std::string> recognizedStrings = std::vector<std::string>(CppMembers::statisticSize);
    std::map<std::string, int> counter;

    cv::Point upperLeftPlateCorner(cv::Size matSize) const {
        cv::Point center = cv::Point(matSize.width/2.0, matSize.height/2.0);
        double plateWidth = plateToImageWidthRatio*matSize.width;
        double plateHeight = plateWidth/plateWidthToHeightRatio;
        return cv::Point(center.x-plateWidth/2.0, center.y-plateHeight/2.0);
    }

    cv::Point upperRightPlateCorner(cv::Size matSize) const {
        cv::Point center = cv::Point(matSize.width/2.0, matSize.height/2.0);
        double plateWidth = plateToImageWidthRatio*matSize.width;
        double plateHeight = plateWidth/plateWidthToHeightRatio;
        return cv::Point(center.x+plateWidth/2.0, center.y-plateHeight/2.0);
    }

    cv::Point lowerLeftPlateCorner(cv::Size matSize) const {
        cv::Point center = cv::Point(matSize.width/2.0, matSize.height/2.0);
        double plateWidth = plateToImageWidthRatio*matSize.width;
        double plateHeight = plateWidth/plateWidthToHeightRatio;
        return cv::Point(center.x-plateWidth/2.0, center.y+plateHeight/2.0);
    }

    cv::Point lowerRightPlateCorner(cv::Size matSize) const {
        cv::Point center = cv::Point(matSize.width/2.0, matSize.height/2.0);
        double plateWidth = plateToImageWidthRatio*matSize.width;
        double plateHeight = plateWidth/plateWidthToHeightRatio;
        return cv::Point(center.x+plateWidth/2.0, center.y+plateHeight/2.0);
    }

    void drawLicensePlateTemplate(cv::Mat& mat) const {
        cv::Point upperLeft = upperLeftPlateCorner(mat.size());
        cv::line(mat, upperLeft, cv::Point(upperLeft.x+markerLen, upperLeft.y), rectangleColor, markerLineWidth);
        cv::line(mat, upperLeft, cv::Point(upperLeft.x, upperLeft.y+markerLen), rectangleColor, markerLineWidth);

        cv::Point upperRight = upperRightPlateCorner(mat.size());
        cv::line(mat, upperRight, cv::Point(upperRight.x-markerLen, upperRight.y), rectangleColor, markerLineWidth);
        cv::line(mat, upperRight, cv::Point(upperRight.x, upperRight.y+markerLen), rectangleColor, markerLineWidth);

        cv::Point lowerLeft = lowerLeftPlateCorner(mat.size());
        cv::line(mat, lowerLeft, cv::Point(lowerLeft.x+markerLen, lowerLeft.y), rectangleColor, markerLineWidth);
        cv::line(mat, lowerLeft, cv::Point(lowerLeft.x, lowerLeft.y-markerLen), rectangleColor, markerLineWidth);

        cv::Point lowerRight = lowerRightPlateCorner(mat.size());
        cv::line(mat, lowerRight, cv::Point(lowerRight.x-markerLen, lowerRight.y), rectangleColor, markerLineWidth);
        cv::line(mat, lowerRight, cv::Point(lowerRight.x, lowerRight.y-markerLen), rectangleColor, markerLineWidth);
    }

    cv::Mat filterPatch(cv::Mat patch) {
        int thresh_patch = 100;

        std::vector<std::vector<cv::Point>> contours;
        std::vector<cv::Vec4i> hierarchy;

        cv::Mat canny;
        cv::Canny(patch, canny, thresh_patch, thresh_patch*2, 3);
        cv::findContours(canny, contours, hierarchy, CV_RETR_TREE, CV_CHAIN_APPROX_SIMPLE, cv::Point(0, 0));

        cv::Mat patch_copy(patch.size(), patch.type());
        patch_copy = cv::Scalar(255, 255, 255);
        for (int i = 0; i < contours.size(); ++i) {
            cv::Rect possible_symbol = cv::boundingRect(cv::Mat(contours[i]));

            // Symbol should be in the middle of a patch
            int symbol_center = possible_symbol.y + possible_symbol.height/2;
            if (std::abs((symbol_center - patch.rows)/patch.rows) > 0.4) {
                // continue;
            }

            // Symbol should have given aspect ratio
            double aspectRatio = possible_symbol.height/(float)possible_symbol.width;
            if (std::abs((aspectRatio - symbolWidthToHeightRatio)/symbolWidthToHeightRatio) > 0.4) {
                // continue;
            }

            // Symbol should be big enough
            if (possible_symbol.height < patch.size().height/2) {
                continue;
            }

            // Symbol should have given area when compared to plate
            double symbolToPlateArea = possible_symbol.area()/(float)patch.size().area();
            if (symbolToPlateArea > 1.8*symbolToPlateAreaRatio || symbolToPlateArea < 0.5*symbolToPlateAreaRatio) {
                //std::cout << "R: " << symbolToPlateArea << " expected: " << symbolToPlateAreaRatio << std::endl;
                continue;
            }

            cv::Mat symbol = cv::Mat(patch, possible_symbol);
            symbol.copyTo(patch_copy(possible_symbol));
        }

        return patch_copy;
    }

    std::pair<float, std::string> statisticProcessor(const std::string& recognized) {
        // Update state
        recognizedStrings[end % statisticSize] = recognized;
        counter[recognized] += 1;
        end += 1;

        // Remove old if necessery
        if (end - begin == statisticSize) {
            std::string oldestString = recognizedStrings[begin % statisticSize];
            counter[oldestString] -= 1;
            begin += 1;
        }

        // Compute most common string
        std::string most_common_string;
        for (const auto& it : counter) {
            if (most_common_string.empty()) {
                most_common_string = it.first;
                continue;
            }
            if (it.second > counter[most_common_string]) {
                most_common_string = it.first;
            }
        }

        for (const auto& it : counter) {
            std::cout << "K: " << it.first << " V: " << it.second << std::endl;
        }

        // Return most common string only if it is very confident
        float confidence = counter[most_common_string] / (float)(statisticSize - 1);
        std::cout << "Confidence (" << most_common_string << "): " << counter[most_common_string] << "/" << statisticSize << std::endl;
        return std::make_pair(confidence, most_common_string);
    }
};

@implementation OcrProcessor

-(id) init {
    self = [super init];
    _cpp = new CppMembers();
    return self;
}

-(void) dealloc {
    delete _cpp;
}

-(UIImage*) process:(UIImage *)image withRotation:(double)rotation {
    cv::Mat mat = [self cvMatFromUIImage:image];
    cv::Mat rot_mat = cv::getRotationMatrix2D(cv::Point(mat.cols/2, mat.rows/2), rotation*180.0/M_PI, 1);
    cv::warpAffine(mat, mat, rot_mat, mat.size(), cv::INTER_CUBIC);
    cv::Mat gray;
    cv::cvtColor(mat, gray, CV_BGRA2GRAY);

    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;

    cv::Point upperLeft = _cpp->upperLeftPlateCorner(mat.size());
    cv::Point lowerRight = _cpp->lowerRightPlateCorner(mat.size());

    int thresh = 100;
    cv::Mat canny_image;
    cv::Canny(gray, canny_image, thresh, thresh*2, 3);
    cv::findContours(canny_image, contours, hierarchy, CV_RETR_TREE, CV_CHAIN_APPROX_SIMPLE, cv::Point(0, 0));

    int minContourIndex = 0;
    double minContourDist = INFINITY;

    for (int i = 0; i < contours.size(); ++i) {
        cv::Rect bbox = cv::boundingRect(cv::Mat(contours[i]));
        //cv::rectangle(mat, bbox, _cpp->contourColor);

        double dist = cv::norm(upperLeft-bbox.tl()) + cv::norm(lowerRight-bbox.br());
        if (dist < minContourDist) {
            minContourIndex = i;
            minContourDist = dist;
        }
    }

    if (minContourIndex < contours.size()) {
        cv::Rect bbox = cv::boundingRect(cv::Mat(contours[minContourIndex]));

        cv::drawContours(mat, contours, minContourIndex, _cpp->contourColor, 2, 8, hierarchy, 0, cv::Point());

        cv::Point bbox_center = cv::Point(bbox.x + bbox.width/2, bbox.y + bbox.height/2);
        cv::Mat patch;
        cv::getRectSubPix(gray, bbox.size(), bbox_center, patch);
        cv::blur(patch, patch, cv::Size(7, 7));
        cv::adaptiveThreshold(patch, patch, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 19, 2);

        cv::Mat patch_processed = _cpp->filterPatch(patch);
        self.licensePlatePatch = [self UIImageFromCVMat:patch_processed];
    }
    _cpp->drawLicensePlateTemplate(mat);
    return [self UIImageFromCVMat:mat];
}

- (NSString*) statisticProcessor: (NSString*)recognized {
    std::string recognizedString(recognized.UTF8String);
    std::pair<float, std::string> result = _cpp->statisticProcessor(recognizedString);
    self.statisticConfidence = result.first;
    std::string statisticallyProcessedString(result.second);
    return [[NSString alloc] initWithUTF8String:statisticallyProcessedString.c_str()];
}

- (cv::Mat)cvMatFromUIImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;

    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels (color channels + alpha)

    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to  data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags

    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

- (cv::Mat)cvMatGrayFromUIImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;

    cv::Mat cvMat(rows, cols, CV_8UC1); // 8 bits per component, 1 channels

    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags

    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

-(UIImage *)UIImageFromCVMat:(cv::Mat)cvMat
{
    NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.elemSize()*cvMat.total()];
    CGColorSpaceRef colorSpace;

    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);

    // Creating CGImage from cv::Mat
    CGImageRef imageRef = CGImageCreate(cvMat.cols,                                 //width
                                        cvMat.rows,                                 //height
                                        8,                                          //bits per component
                                        8 * cvMat.elemSize(),                       //bits per pixel
                                        cvMat.step[0],                            //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );


    // Getting UIImage from CGImage
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}

@end

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScript.h>
#import <JavaScriptCore/JSStringRefCF.h>

#pragma mark func definition
static void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception);
static JSValueRef IDToValue(JSContextRef ctx, id object);
static id ValueToID(JSContextRef ctx, JSValueRef value);

// This is the body of the JavaScript "start()" function.
static JSValueRef RequireCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                  size_t argumentCount, const JSValueRef arguments[],
                                  JSValueRef* exception)
{
    if (argumentCount < 1) {
        return JSValueMakeUndefined(ctx);
    }

    NSString *moduleName = [NSString stringWithFormat:@"%@",ValueToID(ctx, arguments[0])];
    if (![moduleName hasSuffix:@".js"]) { moduleName = [moduleName stringByAppendingString:@".js"]; }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *inputFilepath = [fileManager.currentDirectoryPath stringByAppendingPathComponent:moduleName];
    NSString *input = [NSString stringWithContentsOfFile:inputFilepath encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"require('%@'): evaluating js from %@:\n%@", moduleName, inputFilepath, input);

    NSString *inputExport = [NSString stringWithFormat:@"var exports = {};\n%@;\nreturn exports;",input];
    JSStringRef inputBody = JSStringCreateWithCFString((__bridge CFStringRef)inputExport);

    // Compile the function:
    JSObjectRef fn = JSObjectMakeFunction(ctx, NULL, 0, NULL, inputBody, NULL, 1, exception);

    if (!fn || *exception) {
        WarnJSException(ctx, @"JS function compile failed", *exception);
        return JSValueMakeUndefined(ctx);
    }
    //JSValueProtect(ctx, fn);

    JSValueRef result = JSObjectCallAsFunction(ctx, fn, thisObject, 0, NULL, exception);
    if (*exception) {
        WarnJSException(ctx, @"exception in foojs", *exception);
    }
    // NSLog(@"require('%@'): %@",moduleName, ValueToID(ctx, result));
    return result;
}

// This is the body of the JavaScript "log()" function.
static JSValueRef LogCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                                  size_t argumentCount, const JSValueRef arguments[],
                                  JSValueRef* exception)
{
    NSMutableString *logStr = [NSMutableString string];

    for (size_t i = 0; i < argumentCount; i++) {
        JSValueRef argument = arguments[i];
        id arg = ValueToID(ctx, argument);
        [logStr appendFormat:@"%@", arg];
    }
    NSLog(@"%@", logStr);
    return JSValueMakeUndefined(ctx);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 1 || !strlen(argv[1])) {
            NSLog(@"Please specify input filename");
            exit(EXIT_FAILURE);
        }

        NSString *inputFilename = [NSString stringWithUTF8String:argv[1]];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *inputFilepath = [fileManager.currentDirectoryPath stringByAppendingPathComponent:inputFilename];
        NSString *input = [NSString stringWithContentsOfFile:inputFilepath encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"evaluating js from %@:\n%@", inputFilepath, input);

        JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);

        // callback for log
        JSStringRef logName = JSStringCreateWithCFString(CFSTR("log"));
        JSObjectRef logFn = JSObjectMakeFunctionWithCallback(ctx, logName, &LogCallback);
        JSObjectSetProperty(ctx, JSContextGetGlobalObject(ctx),
                            logName, logFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(logName);

        // callback for require
        JSStringRef requireName = JSStringCreateWithCFString(CFSTR("require"));
        JSObjectRef requireFn = JSObjectMakeFunctionWithCallback(ctx, requireName, &RequireCallback);
        JSObjectSetProperty(ctx, JSContextGetGlobalObject(ctx),
                            requireName, requireFn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(requireName);

        JSStringRef jsBody = JSStringCreateWithCFString((__bridge CFStringRef)input);

        JSValueRef exception = NULL;
        JSValueRef result = JSEvaluateScript(ctx, jsBody, NULL, NULL, 1, &exception);
        if (exception) {
            WarnJSException(ctx, @"exception", exception);
            exit(EXIT_FAILURE);            
        }

        NSLog(@"%@", ValueToID(ctx, result));
    }
    return 0;
}

#pragma mark func implementation
void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception) {
    JSStringRef error = JSValueToStringCopy(context, exception, NULL);
    CFStringRef cfError = error ? JSStringCopyCFString(NULL, error) : NULL;
    NSLog(@"*** WARNING: %@: %@", warning, cfError);
    if (cfError)
        CFRelease(cfError);
}

JSValueRef IDToValue(JSContextRef ctx, id object) {
    if (object == nil) {
        return NULL;
    } else if (object == (id)kCFBooleanFalse || object == (id)kCFBooleanTrue) {
        return JSValueMakeBoolean(ctx, object == (id)kCFBooleanTrue);
    } else if (object == [NSNull null]) {
        return JSValueMakeNull(ctx);
    } else if ([object isKindOfClass: [NSNumber class]]) {
        return JSValueMakeNumber(ctx, [object doubleValue]);
    } else if ([object isKindOfClass: [NSString class]]) {
        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)object);
        JSValueRef value = JSValueMakeString(ctx, jsStr);
        JSStringRelease(jsStr);
        return value;
    } else {
        //FIX: Going through JSON is inefficient.
        NSData* json = [NSJSONSerialization dataWithJSONObject: object options: 0 error: NULL];
        if (!json)
            return NULL;
        NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)jsonStr);
        JSValueRef value = JSValueMakeFromJSONString(ctx, jsStr);
        JSStringRelease(jsStr);
        return value;
    }
}

// Converts a JSON-compatible JSValue to an NSObject.
id ValueToID(JSContextRef ctx, JSValueRef value) {
    if (!value)
        return nil;
    //FIX: Going through JSON is inefficient.
    //TODO: steal idea from https://github.com/ddb/ParseKit/blob/master/jssrc/PKJSUtils.m
    JSStringRef jsStr = JSValueCreateJSONString(ctx, value, 0, NULL);
    if (!jsStr)
        return nil;
    NSString* str = (NSString*)CFBridgingRelease(JSStringCopyCFString(NULL, jsStr));
    JSStringRelease(jsStr);
    str = [NSString stringWithFormat: @"[%@]", str];    // make it a valid JSON object
    NSData* data = [str dataUsingEncoding: NSUTF8StringEncoding];
    NSArray* result = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
    return [result objectAtIndex: 0];
}

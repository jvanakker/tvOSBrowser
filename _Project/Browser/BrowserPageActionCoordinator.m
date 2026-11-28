#import "BrowserPageActionCoordinator.h"

#import "BrowserDOMInteractionService.h"
#import "BrowserNavigationService.h"
#import "BrowserVideoPlaybackCoordinator.h"
#import "BrowserWebView.h"

static UIColor *BrowserPageActionTextColor(void) {
    if (@available(tvOS 13, *)) {
        return UIColor.labelColor;
    } else {
        return UIColor.blackColor;
    }
}

@interface BrowserPageActionCoordinator ()

@property (nonatomic, weak) id<BrowserPageActionCoordinatorHost> host;
@property (nonatomic) BrowserDOMInteractionService *domInteractionService;
@property (nonatomic) BrowserNavigationService *navigationService;
@property (nonatomic) BrowserVideoPlaybackCoordinator *videoPlaybackCoordinator;

@end

@implementation BrowserPageActionCoordinator

- (instancetype)initWithHost:(id<BrowserPageActionCoordinatorHost>)host
       domInteractionService:(BrowserDOMInteractionService *)domInteractionService
           navigationService:(BrowserNavigationService *)navigationService
    videoPlaybackCoordinator:(BrowserVideoPlaybackCoordinator *)videoPlaybackCoordinator {
    self = [super init];
    if (self) {
        _host = host;
        _domInteractionService = domInteractionService;
        _navigationService = navigationService;
        _videoPlaybackCoordinator = videoPlaybackCoordinator;
    }
    return self;
}

- (NSString *)hoverStateAtDOMPoint:(CGPoint)point webView:(BrowserWebView *)webView {
    return [self.domInteractionService evaluateHoverStateJavaScriptAtPoint:point webView:webView];
}

- (BOOL)handleTargetBlankLinkAtDOMPoint:(CGPoint)point webView:(BrowserWebView *)webView {
    NSDictionary *linkInfo = [self.domInteractionService linkInfoAtDOMPoint:point webView:webView];
    NSString *href = [linkInfo[@"href"] isKindOfClass:[NSString class]] ? linkInfo[@"href"] : @"";
    NSString *target = [linkInfo[@"target"] isKindOfClass:[NSString class]] ? linkInfo[@"target"] : @"";

    if (href.length == 0 || ![target isEqualToString:@"_blank"]) {
        return NO;
    }

    NSURLRequest *request = [self.navigationService requestForURLString:href];
    if (request == nil) {
        return NO;
    }

    return [self.host browserPageActionCoordinatorCreateNewTabWithRequest:request];
}

- (void)presentEditableFieldPromptForFieldType:(NSString *)fieldType
                                         point:(CGPoint)point
                                       webView:(BrowserWebView *)webView {
    NSString *editID = NSUUID.UUID.UUIDString;
    NSString *metadataScript = [NSString stringWithFormat:
        @"var target = browserEditableTarget();"
         "if (!target || target.disabled || target.readOnly) return '';"
         "window.__browserKeyboardEdit = { id: '%@', element: target };"
         "var label = target.labels && target.labels.length ? target.labels[0].textContent.trim() : '';"
         "var hint = target.getAttribute('aria-label') || target.placeholder || '';"
         "var completion = (target.autocomplete || '').toLowerCase().split(' ').filter(Boolean);"
         "return JSON.stringify({ title: label || target.title || hint || target.name || '',"
         "  placeholder: hint, value: 'value' in target ? target.value : target.textContent,"
         "  completion: completion, submit: !!(target.form && target.form.hasAttribute('onsubmit')) });", editID];
    NSString *metadataJSON = [self.domInteractionService evaluateEditableElementJavaScriptAtPoint:point
                                                                                          webView:webView
                                                                                             body:metadataScript];
    NSData *data = [metadataJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *metadata = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![metadata isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSString *fieldTitle = [metadata[@"title"] length] ? metadata[@"title"] : fieldType;
    NSString *placeholder = [metadata[@"placeholder"] length] ? metadata[@"placeholder"] : fieldTitle;
    NSArray *completion = metadata[@"completion"];
    BOOL email = [fieldType isEqualToString:@"email"] || [completion containsObject:@"email"] ||
                 [fieldTitle caseInsensitiveCompare:@"email"] == NSOrderedSame;
    BOOL username = [completion containsObject:@"username"];
    BOOL password = [fieldType isEqualToString:@"password"];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Input Text"
                                                                             message:[fieldTitle capitalizedString]
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        if ([fieldType isEqualToString:@"url"]) {
            textField.keyboardType = UIKeyboardTypeURL;
        } else if (email) {
            textField.keyboardType = UIKeyboardTypeEmailAddress;
        } else if ([fieldType isEqualToString:@"tel"] ||
                   [fieldType isEqualToString:@"number"] ||
                   [fieldType isEqualToString:@"date"] ||
                   [fieldType isEqualToString:@"datetime"] ||
                   [fieldType isEqualToString:@"datetime-local"]) {
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        } else {
            textField.keyboardType = UIKeyboardTypeDefault;
        }
        textField.placeholder = [placeholder capitalizedString];
        if (password) {
            textField.secureTextEntry = YES;
            textField.textContentType = [completion containsObject:@"new-password"] ? UITextContentTypeNewPassword : UITextContentTypePassword;
        } else if (username) {
            textField.textContentType = UITextContentTypeUsername;
        } else if (email) {
            textField.textContentType = UITextContentTypeEmailAddress;
        }
        if (email || username || password) {
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.smartQuotesType = UITextSmartQuotesTypeNo;
            textField.smartDashesType = UITextSmartDashesTypeNo;
        }
        textField.text = metadata[@"value"];
        textField.textColor = BrowserPageActionTextColor();
        [textField setReturnKeyType:UIReturnKeyDone];
    }];

    __weak UIAlertController *weakAlert = alertController;
    void (^finishEditing)(BOOL) = ^(BOOL submit) {
        NSString *value = weakAlert.textFields.firstObject.text ?: @"";
        NSString *escapedText = [weakSelf.domInteractionService javaScriptEscapedString:value];
        NSString *commitScript = [NSString stringWithFormat:
            @"(function(){"
             "var edit = window.__browserKeyboardEdit;"
             "if (!edit || edit.id !== '%@' || !edit.element.isConnected) return false;"
             "delete window.__browserKeyboardEdit;"
             "var target = edit.element;"
             "if (target.disabled || target.readOnly) return false;"
             "var value = '%@';"
             "if ('value' in target) { target.value = value; } else { target.textContent = value; }"
             "target.dispatchEvent(new Event('input', { bubbles: true }));"
             "target.dispatchEvent(new Event('change', { bubbles: true }));"
             "if (%@ && target.form && target.isConnected) {"
             "  var form = target.form;"
             "  var button = Array.from(form.elements).find(el => el.type === 'submit');"
             "  if (button) { button.click(); } else if (form.requestSubmit) { form.requestSubmit(); }"
             "}"
             "return true;"
             "})()", editID, escapedText, submit ? @"true" : @"false"];
        [webView stringByEvaluatingJavaScriptFromString:commitScript];
    };
    [alertController addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault
                                                     handler:^(__unused UIAlertAction *action) { finishEditing(NO); }]];
    if ([metadata[@"submit"] boolValue]) {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
                                                         handler:^(__unused UIAlertAction *action) { finishEditing(YES); }]];
    }
    [alertController addAction:[UIAlertAction actionWithTitle:nil style:UIAlertActionStyleCancel handler:nil]];
    [self.host browserPageActionCoordinatorPresentViewController:alertController];

    UITextField *inputTextField = alertController.textFields.firstObject;
    if ([[inputTextField.text stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString:@""]) {
        [inputTextField becomeFirstResponder];
    }
}

- (BOOL)handlePageSelectionAtDOMPoint:(CGPoint)point webView:(BrowserWebView *)webView {
    if ([self.videoPlaybackCoordinator handleSelectPressForVideoAtCursor]) {
        return YES;
    }
    if ([self handleTargetBlankLinkAtDOMPoint:point webView:webView]) {
        return YES;
    }

    NSString *fieldType = [self.domInteractionService evaluateResolvedElementJavaScriptAtPoint:point
                                                                                        webView:webView
                                                                                           body:@"function browserEditableTargetAtPoint() {"
                                                                                                "var candidate = editableElement;"
                                                                                                "if (!candidate && resolvedElement && resolvedElement.matches) {"
                                                                                                    "if (resolvedElement.matches(editableSelector) || resolvedElement.matches('textarea, select')) {"
                                                                                                        "candidate = resolvedElement;"
                                                                                                    "}"
                                                                                                "}"
                                                                                                "if (!candidate) { return null; }"
                                                                                                "window.__browserLastEditableElement = candidate;"
                                                                                                "return candidate;"
                                                                                                "}"
                                                                                                "var target = browserEditableTargetAtPoint();"
                                                                                                "if (!target) { return ''; }"
                                                                                                "var tagName = target.tagName ? target.tagName.toLowerCase() : '';"
                                                                                                "var type = (target.type || '').toLowerCase();"
                                                                                                "if (tagName === 'textarea' || target.isContentEditable) { return 'text'; }"
                                                                                                "if (tagName === 'input' && !type) { return 'text'; }"
                                                                                                "return type;"];
    [self.domInteractionService evaluateResolvedElementJavaScriptAtPoint:point
                                                                 webView:webView
                                                                    body:@"var target = editableElement || interactiveElement || resolvedElement;"
                                                                         "if (!target) { return 'false'; }"
                                                                         "try { if (target.focus) { target.focus(); } } catch (error) {}"
                                                                         "function dispatchPointerLikeEvent(type, constructorName) {"
                                                                             "try {"
                                                                                 "var Constructor = window[constructorName];"
                                                                                 "if (Constructor) {"
                                                                                     "var event = new Constructor(type, { bubbles: true, cancelable: true, composed: true, view: window, clientX: x, clientY: y, screenX: x, screenY: y, button: 0, buttons: 1, pointerType: 'mouse' });"
                                                                                     "return target.dispatchEvent(event);"
                                                                                 "}"
                                                                             "} catch (error) {}"
                                                                             "var mouseEvent = document.createEvent('MouseEvents');"
                                                                             "mouseEvent.initMouseEvent(type, true, true, window, 1, x, y, x, y, false, false, false, false, 0, null);"
                                                                             "return target.dispatchEvent(mouseEvent);"
                                                                         "}"
                                                                         "dispatchPointerLikeEvent('pointerdown', 'PointerEvent');"
                                                                         "dispatchPointerLikeEvent('mousedown', 'MouseEvent');"
                                                                         "dispatchPointerLikeEvent('pointerup', 'PointerEvent');"
                                                                         "dispatchPointerLikeEvent('mouseup', 'MouseEvent');"
                                                                         "if (typeof target.click === 'function') { target.click(); }"
                                                                         "else { dispatchPointerLikeEvent('click', 'MouseEvent'); }"
                                                                         "return 'true';"];
    fieldType = fieldType.lowercaseString;
    if ([fieldType isEqualToString:@"date"] ||
        [fieldType isEqualToString:@"datetime"] ||
        [fieldType isEqualToString:@"datetime-local"] ||
        [fieldType isEqualToString:@"email"] ||
        [fieldType isEqualToString:@"month"] ||
        [fieldType isEqualToString:@"number"] ||
        [fieldType isEqualToString:@"password"] ||
        [fieldType isEqualToString:@"search"] ||
        [fieldType isEqualToString:@"tel"] ||
        [fieldType isEqualToString:@"text"] ||
        [fieldType isEqualToString:@"time"] ||
        [fieldType isEqualToString:@"url"] ||
        [fieldType isEqualToString:@"week"]) {
        [self presentEditableFieldPromptForFieldType:fieldType point:point webView:webView];
    }
    return YES;
}

@end

import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

void main() {
  test('the email steps of a login are steps of their own', () {
    expect(
      map.authState(
        td.AuthorizationStateWaitEmailAddress.fromJson(const {
          '@type': 'authorizationStateWaitEmailAddress',
          'allow_apple_id': false,
          'allow_google_id': false,
        }),
      ),
      isA<AuthWaitEmailAddress>(),
    );
    final code = map.authState(
      td.AuthorizationStateWaitEmailCode.fromJson(const {
        '@type': 'authorizationStateWaitEmailCode',
        'allow_apple_id': false,
        'allow_google_id': false,
        'code_info': {
          '@type': 'emailAddressAuthenticationCodeInfo',
          'email_address_pattern': 'a***@example.com',
          'length': 6,
        },
      }),
    ) as AuthWaitEmailCode;
    expect((code.emailPattern, code.codeLength), ('a***@example.com', 6));
  });

  test('a step the app cannot do is not a spinner', () {
    expect(
      map.authState(
        td.AuthorizationStateWaitPremiumPurchase.fromJson(const {
          '@type': 'authorizationStateWaitPremiumPurchase',
          'store_product_id': 'p',
          'support_email_address': '',
          'support_email_subject': '',
        }),
      ),
      isA<AuthUnsupported>(),
    );
  });

  test('the new states cross the isolate boundary', () {
    for (final s in const [
      AuthWaitEmailAddress(),
      AuthWaitEmailCode(emailPattern: 'a***@example.com', codeLength: 6),
      AuthUnsupported(),
    ]) {
      expect(decodeAuthState(encodeAuthState(s)).runtimeType, s.runtimeType);
    }
    final code = decodeAuthState(
      encodeAuthState(
        const AuthWaitEmailCode(
          emailPattern: 'a***@example.com',
          codeLength: 6,
        ),
      ),
    ) as AuthWaitEmailCode;
    expect((code.emailPattern, code.codeLength), ('a***@example.com', 6));
  });
}

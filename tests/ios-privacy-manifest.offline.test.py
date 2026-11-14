import pathlib
import plistlib
import unittest


class PrivacyManifestTests(unittest.TestCase):
    def test_app_declares_reason_for_its_onboarding_user_defaults(self):
        manifest = pathlib.Path(__file__).resolve().parents[1] / 'ios/JapaneseSyntaxCoach/PrivacyInfo.xcprivacy'
        with manifest.open('rb') as source:
            data = plistlib.load(source)
        entries = data['NSPrivacyAccessedAPITypes']
        user_defaults = [entry for entry in entries if entry.get('NSPrivacyAccessedAPIType') == 'NSPrivacyAccessedAPICategoryUserDefaults']
        self.assertEqual(len(user_defaults), 1, 'Expected one UserDefaults declaration')
        self.assertIn('CA92.1', user_defaults[0]['NSPrivacyAccessedAPITypeReasons'])

    def test_purchase_history_declares_account_link_and_app_functionality(self):
        manifest = pathlib.Path(__file__).resolve().parents[1] / 'ios/JapaneseSyntaxCoach/PrivacyInfo.xcprivacy'
        with manifest.open('rb') as source:
            data = plistlib.load(source)
        entries = [entry for entry in data['NSPrivacyCollectedDataTypes']
                   if entry.get('NSPrivacyCollectedDataType') == 'NSPrivacyCollectedDataTypePurchaseHistory']
        self.assertEqual(len(entries), 1, 'Expected one purchase history declaration')
        self.assertIs(entries[0]['NSPrivacyCollectedDataTypeLinked'], True)
        self.assertIs(entries[0]['NSPrivacyCollectedDataTypeTracking'], False)
        self.assertIn('NSPrivacyCollectedDataTypePurposeAppFunctionality', entries[0]['NSPrivacyCollectedDataTypePurposes'])


if __name__ == '__main__':
    unittest.main()

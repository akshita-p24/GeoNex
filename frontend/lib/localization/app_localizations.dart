import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get navDashboard => _t('navDashboard');
  String get navRiskMap => _t('navRiskMap');
  String get navPriority => _t('navPriority');
  String get navVerification => _t('navVerification');
  String get navReport => _t('navReport');
  String get navAlerts => _t('navAlerts');
  String get navSettings => _t('navSettings');
  String get regionalRiskStatus => _t('regionalRiskStatus');
  String get riskTrend => _t('riskTrend');
  String get confidence => _t('confidence');
  String get login => _t('login');
  String get logout => _t('logout');
  String get username => _t('username');
  String get password => _t('password');
  String get loginTitle => _t('loginTitle');
  String get loginSubtitle => _t('loginSubtitle');
  String get riskOverview => _t('riskOverview');
  String get highRiskZones => _t('highRiskZones');
  String get activeAlerts => _t('activeAlerts');
  String get exposedPopulation => _t('exposedPopulation');
  String get blockedRoads => _t('blockedRoads');
  String get priorityLocations => _t('priorityLocations');
  String get rapidActionWorkflows => _t('rapidActionWorkflows');
  String get lastUpdated => _t('lastUpdated');
  String get viewAll => _t('viewAll');
  String get reportIncident => _t('reportIncident');
  String get fieldVerification => _t('fieldVerification');
  String get actionEngine => _t('actionEngine');
  String get regionalAnalytics => _t('regionalAnalytics');
  String get viewRiskDetails => _t('viewRiskDetails');
  String get getSafeRoute => _t('getSafeRoute');
  String get interactiveRiskMap => _t('interactiveRiskMap');
  String get mapLayers => _t('mapLayers');
  String get mapLayersOverlays => _t('mapLayersOverlays');
  String get riskZones => _t('riskZones');
  String get roadNetworks => _t('roadNetworks');
  String get rainfallHeatmap => _t('rainfallHeatmap');
  String get soilMoisture => _t('soilMoisture');
  String get historicalLandslides => _t('historicalLandslides');
  String get infrastructure => _t('infrastructure');
  String get citizenReports => _t('citizenReports');
  String get statusPending => _t('statusPending');
  String get statusVerified => _t('statusVerified');
  String get statusRejected => _t('statusRejected');
  String get statusEscalated => _t('statusEscalated');
  String get verify => _t('verify');
  String get reject => _t('reject');
  String get needsInformation => _t('needsInformation');
  String get submitReport => _t('submitReport');
  String get incidentType => _t('incidentType');
  String get severity => _t('severity');
  String get notes => _t('notes');
  String get location => _t('location');
  String get alertsTitle => _t('alertsTitle');
  String get settingsTitle => _t('settingsTitle');
  String get language => _t('language');
  String get selectLanguage => _t('selectLanguage');
  String get languageUpdated => _t('languageUpdated');
  String get notificationPreferences => _t('notificationPreferences');
  String get offlineMode => _t('offlineMode');
  String get dataSync => _t('dataSync');
  String get security => _t('security');
  String get switchRole => _t('switchRole');
  String get confirmLogout => _t('confirmLogout');
  String get cancel => _t('cancel');
  String get close => _t('close');
  String get save => _t('save');
  String get submit => _t('submit');
  String get back => _t('back');
  String get refresh => _t('refresh');
  String get search => _t('search');
  String get loading => _t('loading');
  String get noData => _t('noData');

  String _t(String key) {
    return _translations[locale.languageCode]?[key] ??
        _translations['en']![key] ??
        key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'hi', 'as', 'bn', 'ne', 'brx'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

const Map<String, Map<String, String>> _translations = {
  'en': {
    'navDashboard': 'Dashboard',
    'navRiskMap': 'Risk Map',
    'navPriority': 'Priority',
    'navVerification': 'Verification',
    'navReport': 'Report',
    'navAlerts': 'Alerts',
    'navSettings': 'Settings',
    'regionalRiskStatus': 'Regional Risk Status',
    'riskTrend': 'Risk trend',
    'confidence': 'Confidence',
    'login': 'Login',
    'logout': 'Logout',
    'username': 'Username',
    'password': 'Password',
    'loginTitle': 'Terra Sense',
    'loginSubtitle': 'Landslide Risk Monitoring & Action Platform',
    'riskOverview': 'Risk Overview',
    'highRiskZones': 'High Risk Zones',
    'activeAlerts': 'Active Alerts',
    'exposedPopulation': 'Exposed Population',
    'blockedRoads': 'Blocked Roads',
    'priorityLocations': 'Priority Locations',
    'rapidActionWorkflows': 'Rapid Action Workflows',
    'lastUpdated': 'Last Updated',
    'viewAll': 'View All',
    'reportIncident': 'Report Incident',
    'fieldVerification': 'Field Verification',
    'actionEngine': 'Action Engine',
    'regionalAnalytics': 'Regional Analytics',
    'viewRiskDetails': 'View Risk Details',
    'getSafeRoute': 'Get Safe Route',
    'interactiveRiskMap': 'Interactive Risk Map',
    'mapLayers': 'Map Layers',
    'mapLayersOverlays': 'Map Layers & Overlays',
    'riskZones': 'Risk Zones & Hazard Polygons',
    'roadNetworks': 'Road Networks & Arteries',
    'rainfallHeatmap': 'Rainfall Heatmap (IMD)',
    'soilMoisture': 'Soil Moisture Index (SMAP)',
    'historicalLandslides': 'Historical Landslide Scars (GSI)',
    'infrastructure': 'Critical Infrastructure & Hospitals',
    'citizenReports': 'Verified Citizen Reports',
    'statusPending': 'Pending',
    'statusVerified': 'Verified',
    'statusRejected': 'Rejected',
    'statusEscalated': 'Escalated',
    'verify': 'Verify',
    'reject': 'Reject',
    'needsInformation': 'Needs Information',
    'submitReport': 'Submit Report',
    'incidentType': 'Incident Type',
    'severity': 'Severity',
    'notes': 'Notes',
    'location': 'Location',
    'alertsTitle': 'Alerts',
    'settingsTitle': 'Profile / Settings',
    'language': 'Language',
    'selectLanguage': 'Select App Language',
    'languageUpdated': 'Language updated to',
    'notificationPreferences': 'Notification Preferences',
    'offlineMode': 'Offline Mode',
    'dataSync': 'Data Sync',
    'security': 'Security & Integrity',
    'switchRole': 'Switch Active Role',
    'confirmLogout': 'Confirm Logout',
    'cancel': 'Cancel',
    'close': 'Close',
    'save': 'Save',
    'submit': 'Submit',
    'back': 'Back',
    'refresh': 'Refresh',
    'search': 'Search',
    'loading': 'Loading...',
    'noData': 'No data available',
  },
  'hi': {
    'navDashboard': 'डैशबोर्ड',
    'navRiskMap': 'जोखिम मानचित्र',
    'navAlerts': 'अलर्ट',
    'navSettings': 'सेटिंग्स',
    'login': 'लॉगिन',
    'logout': 'लॉगआउट',
    'username': 'उपयोगकर्ता नाम',
    'password': 'पासवर्ड',
    'loginTitle': 'टेरा सेंस',
    'loginSubtitle': 'भूस्खलन जोखिम निगरानी मंच',
    'riskOverview': 'जोखिम अवलोकन',
    'highRiskZones': 'उच्च जोखिम क्षेत्र',
    'activeAlerts': 'सक्रिय अलर्ट',
    'exposedPopulation': 'प्रभावित जनसंख्या',
    'blockedRoads': 'अवरुद्ध सड़कें',
    'priorityLocations': 'प्राथमिकता स्थान',
    'rapidActionWorkflows': 'त्वरित कार्रवाई',
    'lastUpdated': 'अंतिम अपडेट',
    'viewAll': 'सभी देखें',
    'reportIncident': 'घटना रिपोर्ट करें',
    'fieldVerification': 'फ़ील्ड सत्यापन',
    'actionEngine': 'कार्रवाई इंजन',
    'regionalAnalytics': 'क्षेत्रीय विश्लेषण',
    'viewRiskDetails': 'जोखिम विवरण देखें',
    'getSafeRoute': 'सुरक्षित मार्ग',
    'interactiveRiskMap': 'इंटरेक्टिव जोखिम मानचित्र',
    'mapLayers': 'मानचित्र परतें',
    'mapLayersOverlays': 'मानचित्र परतें और ओवरले',
    'riskZones': 'जोखिम क्षेत्र',
    'roadNetworks': 'सड़क नेटवर्क',
    'rainfallHeatmap': 'वर्षा हीटमैप',
    'soilMoisture': 'मृदा आर्द्रता सूचकांक',
    'historicalLandslides': 'ऐतिहासिक भूस्खलन (जीएसआई)',
    'infrastructure': 'महत्वपूर्ण अवसंरचना',
    'citizenReports': 'नागरिक रिपोर्ट',
    'statusPending': 'लंबित',
    'statusVerified': 'सत्यापित',
    'statusRejected': 'अस्वीकृत',
    'statusEscalated': 'एस्केलेटेड',
    'verify': 'सत्यापित करें',
    'reject': 'अस्वीकार करें',
    'needsInformation': 'अधिक जानकारी चाहिए',
    'submitReport': 'रिपोर्ट जमा करें',
    'incidentType': 'घटना प्रकार',
    'severity': 'गंभीरता',
    'notes': 'नोट्स',
    'location': 'स्थान',
    'alertsTitle': 'अलर्ट',
    'settingsTitle': 'प्रोफाइल / सेटिंग्स',
    'language': 'भाषा',
    'selectLanguage': 'भाषा चुनें',
    'languageUpdated': 'भाषा बदली गई',
    'notificationPreferences': 'अधिसूचना प्राथमिकताएं',
    'offlineMode': 'ऑफलाइन मोड',
    'dataSync': 'डेटा सिंक',
    'security': 'सुरक्षा',
    'switchRole': 'भूमिका बदलें',
    'confirmLogout': 'लॉगआउट की पुष्टि करें',
    'cancel': 'रद्द करें',
    'close': 'बंद करें',
    'save': 'सहेजें',
    'submit': 'जमा करें',
    'back': 'वापस',
    'refresh': 'रीफ्रेश',
    'search': 'खोज',
    'loading': 'लोड हो रहा है...',
    'noData': 'कोई डेटा उपलब्ध नहीं',
  },
  'as': {
    'navDashboard': 'ড্যাশব\'ৰ্ড',
    'navRiskMap': 'বিপদ মানচিত্ৰ',
    'navAlerts': 'সতৰ্কবাৰ্তা',
    'navSettings': 'ছেটিংছ',
    'login': 'লগইন',
    'logout': 'লগআউট',
    'username': 'ব্যৱহাৰকাৰীৰ নাম',
    'password': 'পাছৱৰ্ড',
    'loginTitle': 'টেৰা চেন্স',
    'loginSubtitle': 'ভূমিস্খলন বিপদ নিৰীক্ষণ',
    'riskOverview': 'বিপদৰ সংক্ষিপ্ত বিৱৰণ',
    'highRiskZones': 'উচ্চ বিপদ অঞ্চল',
    'activeAlerts': 'সক্ৰিয় সতৰ্কবাৰ্তা',
    'exposedPopulation': 'ক্ষতিগ্ৰস্ত জনসংখ্যা',
    'blockedRoads': 'অৱৰুদ্ধ পথ',
    'priorityLocations': 'অগ্ৰাধিকাৰ স্থান',
    'rapidActionWorkflows': 'দ্ৰুত পদক্ষেপ',
    'lastUpdated': 'শেষ আপডেট',
    'viewAll': 'সকলো চাওক',
    'reportIncident': 'ঘটনা প্ৰতিবেদন',
    'fieldVerification': 'ফিল্ড যাচাই',
    'actionEngine': 'কাৰ্য ইঞ্জিন',
    'regionalAnalytics': 'আঞ্চলিক বিশ্লেষণ',
    'viewRiskDetails': 'বিপদৰ বিৱৰণ চাওক',
    'getSafeRoute': 'নিৰাপদ পথ',
    'interactiveRiskMap': 'ইন্টাৰেক্টিভ বিপদ মানচিত্ৰ',
    'mapLayers': 'মানচিত্ৰ স্তৰ',
    'mapLayersOverlays': 'মানচিত্ৰ স্তৰ আৰু অভাৰলে',
    'riskZones': 'বিপদ অঞ্চল',
    'roadNetworks': 'পথ নেটৱৰ্ক',
    'rainfallHeatmap': 'বৰষুণ হিটমেপ',
    'soilMoisture': 'মাটিৰ আৰ্দ্ৰতা',
    'historicalLandslides': 'ঐতিহাসিক ভূমিস্খলন',
    'infrastructure': 'গুৰুত্বপূৰ্ণ আন্তঃগাঁথনি',
    'citizenReports': 'নাগৰিক প্ৰতিবেদন',
    'statusPending': 'বিচাৰাধীন',
    'statusVerified': 'যাচাই কৰা',
    'statusRejected': 'প্ৰত্যাখ্যাত',
    'statusEscalated': 'এস্কেলেটেড',
    'verify': 'যাচাই কৰক',
    'reject': 'প্ৰত্যাখ্যান কৰক',
    'needsInformation': 'অধিক তথ্য প্ৰয়োজন',
    'submitReport': 'প্ৰতিবেদন দাখিল কৰক',
    'incidentType': 'ঘটনাৰ প্ৰকাৰ',
    'severity': 'গুৰুত্ব',
    'notes': 'টোকা',
    'location': 'স্থান',
    'alertsTitle': 'সতৰ্কবাৰ্তা',
    'settingsTitle': 'প্ৰ\'ফাইল / ছেটিংছ',
    'language': 'ভাষা',
    'selectLanguage': 'এপৰ ভাষা বাছক',
    'languageUpdated': 'ভাষা আপডেট হ\'ল',
    'notificationPreferences': 'জাননীৰ পছন্দ',
    'offlineMode': 'অফলাইন মোড',
    'dataSync': 'ডেটা চিংক',
    'security': 'সুৰক্ষা',
    'switchRole': 'ভূমিকা সলনি কৰক',
    'confirmLogout': 'লগআউট নিশ্চিত কৰক',
    'cancel': 'বাতিল',
    'close': 'বন্ধ কৰক',
    'save': 'সংৰক্ষণ কৰক',
    'submit': 'দাখিল কৰক',
    'back': 'উভতি যাওক',
    'refresh': 'ৰিফ্ৰেচ',
    'search': 'সন্ধান কৰক',
    'loading': 'লোড হৈছে...',
    'noData': 'কোনো তথ্য নাই',
  },
  'bn': {
    'navDashboard': 'ড্যাশবোর্ড',
    'navRiskMap': 'ঝুঁকি মানচিত্র',
    'navAlerts': 'সতর্কতা',
    'navSettings': 'সেটিংস',
    'login': 'লগইন',
    'logout': 'লগআউট',
    'username': 'ব্যবহারকারীর নাম',
    'password': 'পাসওয়ার্ড',
    'loginTitle': 'টেরা সেন্স',
    'loginSubtitle': 'ভূমিধস ঝুঁকি পর্যবেক্ষণ প্ল্যাটফর্ম',
    'riskOverview': 'ঝুঁকির সারসংক্ষেপ',
    'highRiskZones': 'উচ্চ ঝুঁকি অঞ্চল',
    'activeAlerts': 'সক্রিয় সতর্কতা',
    'exposedPopulation': 'ক্ষতিগ্রস্ত জনগোষ্ঠী',
    'blockedRoads': 'অবরুদ্ধ রাস্তা',
    'priorityLocations': 'অগ্রাধিকার অবস্থান',
    'rapidActionWorkflows': 'দ্রুত পদক্ষেপ',
    'lastUpdated': 'সর্বশেষ আপডেট',
    'viewAll': 'সব দেখুন',
    'reportIncident': 'ঘটনা রিপোর্ট',
    'fieldVerification': 'ফিল্ড যাচাই',
    'actionEngine': 'অ্যাকশন ইঞ্জিন',
    'regionalAnalytics': 'আঞ্চলিক বিশ্লেষণ',
    'viewRiskDetails': 'ঝুঁকির বিস্তারিত',
    'getSafeRoute': 'নিরাপদ পথ',
    'interactiveRiskMap': 'ইন্টারেক্টিভ ঝুঁকি মানচিত্র',
    'mapLayers': 'মানচিত্র স্তর',
    'mapLayersOverlays': 'মানচিত্র স্তর ও ওভারলে',
    'riskZones': 'ঝুঁকি অঞ্চল',
    'roadNetworks': 'সড়ক নেটওয়ার্ক',
    'rainfallHeatmap': 'বৃষ্টিপাত হিটম্যাপ',
    'soilMoisture': 'মাটির আর্দ্রতা সূচক',
    'historicalLandslides': 'ঐতিহাসিক ভূমিধস (জিএসআই)',
    'infrastructure': 'গুরুত্বপূর্ণ অবকাঠামো',
    'citizenReports': 'নাগরিক রিপোর্ট',
    'statusPending': 'মুলতুবি',
    'statusVerified': 'যাচাইকৃত',
    'statusRejected': 'প্রত্যাখ্যাত',
    'statusEscalated': 'এস্কেলেটেড',
    'verify': 'যাচাই করুন',
    'reject': 'প্রত্যাখ্যান করুন',
    'needsInformation': 'আরও তথ্য প্রয়োজন',
    'submitReport': 'রিপোর্ট জমা দিন',
    'incidentType': 'ঘটনার ধরন',
    'severity': 'তীব্রতা',
    'notes': 'নোট',
    'location': 'অবস্থান',
    'alertsTitle': 'সতর্কতা',
    'settingsTitle': 'প্রোফাইল / সেটিংস',
    'language': 'ভাষা',
    'selectLanguage': 'অ্যাপের ভাষা নির্বাচন করুন',
    'languageUpdated': 'ভাষা আপডেট হয়েছে',
    'notificationPreferences': 'বিজ্ঞপ্তির পছন্দ',
    'offlineMode': 'অফলাইন মোড',
    'dataSync': 'ডেটা সিঙ্ক',
    'security': 'নিরাপত্তা',
    'switchRole': 'ভূমিকা পরিবর্তন',
    'confirmLogout': 'লগআউট নিশ্চিত করুন',
    'cancel': 'বাতিল',
    'close': 'বন্ধ করুন',
    'save': 'সংরক্ষণ',
    'submit': 'জমা দিন',
    'back': 'পিছনে',
    'refresh': 'রিফ্রেশ',
    'search': 'অনুসন্ধান',
    'loading': 'লোড হচ্ছে...',
    'noData': 'কোনো ডেটা নেই',
  },
  'ne': {
    'navDashboard': 'ड्यासबोर्ड',
    'navRiskMap': 'जोखिम नक्सा',
    'navAlerts': 'सतर्कता',
    'navSettings': 'सेटिङ',
    'login': 'लगइन',
    'logout': 'लगआउट',
    'username': 'प्रयोगकर्ता नाम',
    'password': 'पासवर्ड',
    'loginTitle': 'टेरा सेन्स',
    'loginSubtitle': 'भूस्खलन जोखिम निगरानी मञ्च',
    'riskOverview': 'जोखिम अवलोकन',
    'highRiskZones': 'उच्च जोखिम क्षेत्र',
    'activeAlerts': 'सक्रिय सतर्कता',
    'exposedPopulation': 'जोखिममा जनसंख्या',
    'blockedRoads': 'अवरुद्ध सडकहरू',
    'priorityLocations': 'प्राथमिकता स्थानहरू',
    'rapidActionWorkflows': 'द्रुत कार्य',
    'lastUpdated': 'अन्तिम अपडेट',
    'viewAll': 'सबै हेर्नुहोस्',
    'reportIncident': 'घटना रिपोर्ट',
    'fieldVerification': 'फिल्ड सत्यापन',
    'actionEngine': 'कार्य इन्जिन',
    'regionalAnalytics': 'क्षेत्रीय विश्लेषण',
    'viewRiskDetails': 'जोखिम विवरण हेर्नुहोस्',
    'getSafeRoute': 'सुरक्षित मार्ग',
    'interactiveRiskMap': 'इन्टरेक्टिभ जोखिम नक्सा',
    'mapLayers': 'नक्सा तहरू',
    'mapLayersOverlays': 'नक्सा तहरू र ओभरले',
    'riskZones': 'जोखिम क्षेत्रहरू',
    'roadNetworks': 'सडक नेटवर्क',
    'rainfallHeatmap': 'वर्षा हिटम्याप',
    'soilMoisture': 'माटोको आर्द्रता सूचकाङ्क',
    'historicalLandslides': 'ऐतिहासिक भूस्खलन',
    'infrastructure': 'महत्वपूर्ण पूर्वाधार',
    'citizenReports': 'नागरिक रिपोर्ट',
    'statusPending': 'विचाराधीन',
    'statusVerified': 'प्रमाणित',
    'statusRejected': 'अस्वीकृत',
    'statusEscalated': 'एस्केलेटेड',
    'verify': 'प्रमाणित गर्नुहोस्',
    'reject': 'अस्वीकार गर्नुहोस्',
    'needsInformation': 'थप जानकारी चाहिन्छ',
    'submitReport': 'रिपोर्ट पेश गर्नुहोस्',
    'incidentType': 'घटनाको प्रकार',
    'severity': 'गम्भीरता',
    'notes': 'नोट',
    'location': 'स्थान',
    'alertsTitle': 'सतर्कता',
    'settingsTitle': 'प्रोफाइल / सेटिङ',
    'language': 'भाषा',
    'selectLanguage': 'एप भाषा छान्नुहोस्',
    'languageUpdated': 'भाषा अपडेट भयो',
    'notificationPreferences': 'सूचना प्राथमिकता',
    'offlineMode': 'अफलाइन मोड',
    'dataSync': 'डेटा सिङ्क',
    'security': 'सुरक्षा',
    'switchRole': 'भूमिका बदल्नुहोस्',
    'confirmLogout': 'लगआउट पुष्टि गर्नुहोस्',
    'cancel': 'रद्द गर्नुहोस्',
    'close': 'बन्द गर्नुहोस्',
    'save': 'बचत गर्नुहोस्',
    'submit': 'पेश गर्नुहोस्',
    'back': 'पछाडि',
    'refresh': 'रिफ्रेस',
    'search': 'खोज्नुहोस्',
    'loading': 'लोड हुदैछ...',
    'noData': 'कुनै डेटा छैन',
  },
  'brx': {
    'navDashboard': 'ड्यासबर\'ड',
    'navRiskMap': 'बिफाव मनखोन',
    'navAlerts': 'सर्तखिनि',
    'navSettings': 'सेटिङ',
    'login': 'लगइन',
    'logout': 'लगआउट',
    'username': 'आबमि नों',
    'password': 'पाछवड',
    'loginTitle': 'टेरा सेन्स',
    'loginSubtitle': 'खुंथाम बिफाव गुबुन फोरखौ थाखो',
    'riskOverview': 'बिफाव गुबुन',
    'highRiskZones': 'बोरो बिफाव गाव',
    'activeAlerts': 'थारैनो सर्तखिनि',
    'exposedPopulation': 'फोर्साबो मानुस',
    'blockedRoads': 'सिराय नाङा रास्ता',
    'priorityLocations': 'बिजाबनि गाव',
    'rapidActionWorkflows': 'नालामसोब गोरोन',
    'lastUpdated': 'गोलैसो आपडेट',
    'viewAll': 'सकल हाबो',
    'reportIncident': 'खामानि रिपर्ट',
    'fieldVerification': 'फिल्ड गाहायनाय',
    'actionEngine': 'गोरोन इञ्जिन',
    'regionalAnalytics': 'गाव विश्लेषण',
    'viewRiskDetails': 'बिफाव बिबार',
    'getSafeRoute': 'सुरोखा नाङा',
    'interactiveRiskMap': 'इन्टरेक्टिभ बिफाव मनखोन',
    'mapLayers': 'मनखोन लेयर',
    'mapLayersOverlays': 'मनखोन लेयर आरो ओभरले',
    'riskZones': 'बिफाव गाव',
    'roadNetworks': 'रास्ता नेटवर्क',
    'rainfallHeatmap': 'बरखा हिटम्याप',
    'soilMoisture': 'दैमा सूचकाङ्क',
    'historicalLandslides': 'थां खुंथाम बिफाव',
    'infrastructure': 'बिजाब बलाङ',
    'citizenReports': 'मानुस रिपर्ट',
    'statusPending': 'थखोन',
    'statusVerified': 'गाहायना',
    'statusRejected': 'माब्लाबना',
    'statusEscalated': 'एस्केलेटेड',
    'verify': 'गाहाय',
    'reject': 'माब्लाब',
    'needsInformation': 'आरो बिबार दरकार',
    'submitReport': 'रिपर्ट पाखा',
    'incidentType': 'खामानि जाथाय',
    'severity': 'बोरो आव',
    'notes': 'टिपनि',
    'location': 'गाव',
    'alertsTitle': 'सर्तखिनि',
    'settingsTitle': 'प्रोफाइल / सेटिङ',
    'language': 'भाषा',
    'selectLanguage': 'एप भाषा सायख',
    'languageUpdated': 'भाषा आपडेट',
    'notificationPreferences': 'जानानाय',
    'offlineMode': 'अफलाइन',
    'dataSync': 'डेटा सिङ्क',
    'security': 'सुरोखा',
    'switchRole': 'भूमिका बादला',
    'confirmLogout': 'लगआउट गाहाय',
    'cancel': 'माब्लाब',
    'close': 'बन्द',
    'save': 'राख',
    'submit': 'पाखा',
    'back': 'उल्टा',
    'refresh': 'रिफ्रेस',
    'search': 'बिनो',
    'loading': 'लोड...',
    'noData': 'डेटा नेई',
  },
};

extension AppLocalizationsX on BuildContext {
  AppLocalizations get loc => AppLocalizations.of(this);
}

/// Exact Baidu CarLife protocol constants ported from `ft-app` (`CarLifeProtocol.kt` & `Prefs.kt`).
class CarLifeProtocol {
  const CarLifeProtocol._();

  // Channel Identifiers
  static const int chCmd = 1;
  static const int chVideo = 2;
  static const int chMedia = 3;
  static const int chTts = 4;
  static const int chVr = 5;
  static const int chCtrl = 6;

  // Standard Wireless TCP Ports (Phone = Server, Car Head Unit = Client)
  static const int defaultCmdPort = 7240;
  static const int defaultVideoPort = 8240;
  static const int defaultMediaPort = 9240;
  static const int defaultTtsPort = 9241;
  static const int defaultVrPort = 9242;
  static const int defaultTouchPort = 9340;

  static const Map<int, int> defaultPorts = {
    chCmd: defaultCmdPort,
    chVideo: defaultVideoPort,
    chMedia: defaultMediaPort,
    chTts: defaultTtsPort,
    chVr: defaultVrPort,
    chCtrl: defaultTouchPort,
  };

  // Header & Body Limits
  static const int headCmd = 8;
  static const int headStream = 12;
  static const int discoveryPort = 7999;
  static const int helloPort = 8999;

  static const int maxCmdBody = 40 * 1024;
  static const int maxStreamBody = 4 * 1024 * 1024;

  // Command Channel Service IDs (CH_CMD = 1)
  static const int cmdHuProtocolVersion = 0x00018001;
  static const int cmdProtocolVersionMatchStatus = 0x00010002;
  static const int cmdHuInfo = 0x00018003;
  static const int cmdMdInfo = 0x00010004;
  static const int cmdMdManualDisconnect = 0x00010077;
  static const int cmdHuBtPairInfo = 0x00018005;
  static const int cmdMdBtPairInfo = 0x00010006;
  static const int cmdVideoEncoderInit = 0x00018007;
  static const int cmdVideoEncoderInitDone = 0x00010008;
  static const int cmdVideoEncoderStart = 0x00018009;
  static const int cmdVideoEncoderPause = 0x0001800A;
  static const int cmdVideoEncoderReset = 0x0001800B;
  static const int cmdVideoEncoderFrameRateChange = 0x0001800C;
  static const int cmdVideoEncoderFrameRateChangeDone = 0x0001000D;
  static const int cmdPauseMedia = 0x0001800E;
  static const int cmdCarVelocity = 0x0001800F;
  static const int cmdCarGps = 0x00018010;
  static const int cmdCarGyroscope = 0x00018011;
  static const int cmdCarAcceleration = 0x00018012;
  static const int cmdCarOil = 0x00018013;
  static const int cmdTeleStateChangeIncoming = 0x00010014;
  static const int cmdTeleStateChangeOutgoing = 0x00010015;
  static const int cmdTeleStateChangeIdle = 0x00010016;
  static const int cmdTeleStateChangeIncalling = 0x00010017;
  static const int cmdScreenOn = 0x00010018;
  static const int cmdScreenOff = 0x00010019;
  static const int cmdScreenUserPresent = 0x0001001A;
  static const int cmdForeground = 0x0001001B;
  static const int cmdBackground = 0x0001001C;
  static const int cmdLaunchModeNormal = 0x0001801D;
  static const int cmdLaunchModePhone = 0x0001801E;
  static const int cmdLaunchModeMap = 0x0001801F;
  static const int cmdLaunchModeMusic = 0x00018020;
  static const int cmdGoToDesktop = 0x00010021;
  static const int cmdMicRecordWakeupStart = 0x00010022;
  static const int cmdMicRecordEnd = 0x00010023;
  static const int cmdMicRecordRecogStart = 0x00010024;
  static const int cmdGoToForeground = 0x00018025;
  static const int cmdModuleStatus = 0x00010026;
  static const int cmdStatisticInfo = 0x00018027;
  static const int cmdModuleControl = 0x00018028;
  static const int cmdGearInfo = 0x00010029;
  static const int cmdHuGearInfo = 0x00018029;
  static const int cmdNaviNextTurnInfo = 0x00010030;
  static const int cmdCarDataSubscribe = 0x00010031;
  static const int cmdCarDataSubscribeDone = 0x00010032;
  static const int cmdCarDataSubscribeStart = 0x00010033;
  static const int cmdCarDataSubscribeStop = 0x00010034;
  static const int cmdMediaInfo = 0x00010035;
  static const int cmdMediaProgressBar = 0x00010036;
  static const int cmdConnectException = 0x00010037;
  static const int cmdRequestGoToForeground = 0x00010038;
  static const int cmdUiActionSound = 0x00010039;
  static const int cmdBtHfpRequest = 0x00010040;
  static const int cmdBtHfpIndication = 0x00018041;
  static const int cmdBtHfpConnection = 0x00018042;
  static const int cmdCarlifeDataSubscribe = 0x00018043;
  static const int cmdCarlifeDataSubscribeDone = 0x00010044;
  static const int cmdCarlifeDataSubscribeStart = 0x00018045;
  static const int cmdCarlifeDataSubscribeStop = 0x00018046;
  static const int cmdNaviAssistantGuideInfo = 0x00010047;
  static const int cmdHuAuthenRequest = 0x00018048;
  static const int cmdMdAuthenResponse = 0x00010049;
  static const int cmdHuAuthenResult = 0x0001804A;
  static const int cmdMdAuthenResult = 0x0001004B;
  static const int cmdGoToForegroundResponse = 0x0001004C;
  static const int cmdStartBtAutopairRequest = 0x0001004D;
  static const int cmdBtHfpResponse = 0x0001804E;
  static const int cmdBtHfpStatusRequest = 0x0001004F;
  static const int cmdBtHfpStatusResponse = 0x00018050;
  static const int cmdMdFeatureConfigRequest = 0x00010051;
  static const int cmdHuFeatureConfigResponse = 0x00018052;
  static const int cmdMdRsaPublicKeyRequest = 0x0001006A;
  static const int cmdHuRsaPublicKeyResponse = 0x0001806B;
  static const int cmdMdAesKeySendRequest = 0x0001006C;
  static const int cmdHuAesRecResponse = 0x0001806D;
  static const int cmdMdEncryptReady = 0x0001006E;
  static const int cmdBtStartIdentifyReq = 0x00018053;
  static const int cmdBtIdentifyResultInd = 0x00010054;
  static const int cmdErrorCode = 0x00018055;
  static const int cmdVideoEncoderJpeg = 0x00018056;
  static const int cmdVideoEncoderJpegAck = 0x00010057;
  static const int cmdBtHfpCallStatusCover = 0x00010058;
  static const int cmdMdExit = 0x00010059;
  static const int cmdVehicleForeground = 0x00018097;
  static const int cmdVehicleBackground = 0x00018098;

  // Wireless Bootstrap Command IDs (CarWirelessSetup.kt)
  static const int mdWirelessInfoRequest = 0x00100001;
  static const int huWirelessInfo = 0x00108002;
  static const int mdTargetInfoRequest = 0x00100004;
  static const int huTargetInfo = 0x00108005;
  static const int huIpRequest = 0x00108006;
  static const int mdWifiIp = 0x00100007;
  static const int huStatus = 0x00108009;

  // Video Channel Service IDs (CH_VIDEO = 2)
  static const int videoData = 0x00020001;
  static const int videoHeartbeat = 0x00020002;

  // Media Channel Service IDs (CH_MEDIA = 3)
  static const int mediaInit = 0x00030001;
  static const int mediaStop = 0x00030002;
  static const int mediaPause = 0x00030003;
  static const int mediaResumePlay = 0x00030004;
  static const int mediaSeekTo = 0x00030005;
  static const int mediaData = 0x00030006;

  // TTS Channel Service IDs (CH_TTS = 4)
  static const int ttsInit = 0x00040001;
  static const int ttsEnd = 0x00040002;
  static const int ttsData = 0x00040003;

  // Touch & Control Channel Service IDs (CH_CTRL = 6)
  static const int touchAction = 0x00068001;
  static const int touchDown = 0x00068002;
  static const int touchUp = 0x00068003;
  static const int touchMove = 0x00068004;
  static const int touchSingleClick = 0x00068005;
  static const int touchDoubleClick = 0x00068006;
  static const int touchLongPress = 0x00068007;
  static const int carHardKeyCode = 0x00068008;
  static const int touchUiActionBegin = 0x0006800A;
  static const int touchPointerDown = 0x0006800B;
  static const int touchPointerUp = 0x0006800C;
  static const int touchOtherPointerUp = 0x0006800D;

  // Module Identifiers
  static const int modulePhone = 1;
  static const int moduleNavi = 2;
  static const int moduleMusic = 3;
  static const int moduleVr = 4;
  static const int moduleMic = 6;

  static String name(int id) {
    switch (id) {
      case cmdHuProtocolVersion:
        return 'HU_PROTOCOL_VERSION';
      case cmdProtocolVersionMatchStatus:
        return 'PROTOCOL_VERSION_MATCH_STATUS';
      case cmdHuInfo:
        return 'HU_INFO';
      case cmdMdInfo:
        return 'MD_INFO';
      case cmdMdManualDisconnect:
        return 'MD_MANUAL_DISCONNECT';
      case cmdHuBtPairInfo:
        return 'HU_BT_PAIR_INFO';
      case cmdMdBtPairInfo:
        return 'MD_BT_PAIR_INFO';
      case cmdVideoEncoderInit:
        return 'VIDEO_ENCODER_INIT';
      case cmdVideoEncoderInitDone:
        return 'VIDEO_ENCODER_INIT_DONE';
      case cmdVideoEncoderStart:
        return 'VIDEO_ENCODER_START';
      case cmdVideoEncoderPause:
        return 'VIDEO_ENCODER_PAUSE';
      case cmdVideoEncoderReset:
        return 'VIDEO_ENCODER_RESET';
      case cmdVideoEncoderFrameRateChange:
        return 'VIDEO_ENCODER_FRAME_RATE_CHANGE';
      case cmdVideoEncoderFrameRateChangeDone:
        return 'VIDEO_ENCODER_FRAME_RATE_CHANGE_DONE';
      case cmdForeground:
        return 'FOREGROUND';
      case cmdBackground:
        return 'BACKGROUND';
      case cmdLaunchModeNormal:
        return 'LAUNCH_MODE_NORMAL';
      case cmdLaunchModePhone:
        return 'LAUNCH_MODE_PHONE';
      case cmdLaunchModeMap:
        return 'LAUNCH_MODE_MAP';
      case cmdLaunchModeMusic:
        return 'LAUNCH_MODE_MUSIC';
      case cmdGoToForeground:
        return 'GO_TO_FOREGROUND';
      case cmdModuleStatus:
        return 'MODULE_STATUS';
      case cmdStatisticInfo:
        return 'STATISTIC_INFO';
      case cmdModuleControl:
        return 'MODULE_CONTROL';
      case cmdHuGearInfo:
        return 'HU_GEAR_INFO';
      case cmdPauseMedia:
        return 'PAUSE_MEDIA';
      case cmdMediaInfo:
        return 'MEDIA_INFO';
      case cmdMediaProgressBar:
        return 'MEDIA_PROGRESS_BAR';
      case cmdNaviNextTurnInfo:
        return 'NAVI_NEXT_TURN_INFO';
      case cmdConnectException:
        return 'CONNECT_EXCEPTION';
      case cmdHuAuthenRequest:
        return 'HU_AUTHEN_REQUEST';
      case cmdMdAuthenResponse:
        return 'MD_AUTHEN_RESPONSE';
      case cmdHuAuthenResult:
        return 'HU_AUTHEN_RESULT';
      case cmdMdAuthenResult:
        return 'MD_AUTHEN_RESULT';
      case cmdGoToForegroundResponse:
        return 'GO_TO_FOREGROUND_RESPONSE';
      case cmdMdFeatureConfigRequest:
        return 'MD_FEATURE_CONFIG_REQUEST';
      case cmdHuFeatureConfigResponse:
        return 'HU_FEATURE_CONFIG_RESPONSE';
      case cmdMdRsaPublicKeyRequest:
        return 'MD_RSA_PUBLIC_KEY_REQUEST';
      case cmdHuRsaPublicKeyResponse:
        return 'HU_RSA_PUBLIC_KEY_RESPONSE';
      case cmdMdAesKeySendRequest:
        return 'MD_AES_KEY_SEND_REQUEST';
      case cmdHuAesRecResponse:
        return 'HU_AES_REC_RESPONSE';
      case cmdMdEncryptReady:
        return 'MD_ENCRYPT_READY';
      case cmdErrorCode:
        return 'ERROR_CODE';
      case cmdMdExit:
        return 'MD_EXIT';
      case cmdVehicleForeground:
        return 'VEHICLE_FOREGROUND';
      case cmdVehicleBackground:
        return 'VEHICLE_BACKGROUND';
      case cmdScreenOn:
        return 'SCREEN_ON';
      case cmdScreenOff:
        return 'SCREEN_OFF';
      case cmdScreenUserPresent:
        return 'SCREEN_USERPRESENT';
      case cmdGoToDesktop:
        return 'GO_TO_DESKTOP';
      case cmdCarlifeDataSubscribe:
        return 'CARLIFE_DATA_SUBSCRIBE';
      case cmdCarlifeDataSubscribeDone:
        return 'CARLIFE_DATA_SUBSCRIBE_DONE';
      case cmdCarlifeDataSubscribeStart:
        return 'CARLIFE_DATA_SUBSCRIBE_START';
      case cmdCarlifeDataSubscribeStop:
        return 'CARLIFE_DATA_SUBSCRIBE_STOP';
      case videoData:
        return 'VIDEO_DATA';
      case videoHeartbeat:
        return 'VIDEO_HEARTBEAT';
      case mediaInit:
        return 'MEDIA_INIT';
      case mediaStop:
        return 'MEDIA_STOP';
      case mediaPause:
        return 'MEDIA_PAUSE';
      case mediaResumePlay:
        return 'MEDIA_RESUME_PLAY';
      case mediaSeekTo:
        return 'MEDIA_SEEK_TO';
      case mediaData:
        return 'MEDIA_DATA';
      case ttsInit:
        return 'TTS_INIT';
      case ttsEnd:
        return 'TTS_END';
      case ttsData:
        return 'TTS_DATA';
      case touchAction:
        return 'TOUCH_ACTION';
      case touchDown:
        return 'TOUCH_DOWN';
      case touchUp:
        return 'TOUCH_UP';
      case touchMove:
        return 'TOUCH_MOVE';
      case touchSingleClick:
        return 'TOUCH_SINGLE_CLICK';
      case touchDoubleClick:
        return 'TOUCH_DOUBLE_CLICK';
      case touchLongPress:
        return 'TOUCH_LONG_PRESS';
      case touchUiActionBegin:
        return 'TOUCH_UI_ACTION_BEGIN';
      case touchPointerDown:
        return 'TOUCH_POINTER_DOWN';
      case touchPointerUp:
        return 'TOUCH_POINTER_UP';
      case touchOtherPointerUp:
        return 'TOUCH_OTHERPOINTER_UP';
      case carHardKeyCode:
        return 'CAR_HARD_KEY_CODE';
      default:
        return '0x${id.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }
  }

  static String channelName(int ch) {
    switch (ch) {
      case chCmd:
        return 'CMD';
      case chVideo:
        return 'VIDEO';
      case chMedia:
        return 'MEDIA';
      case chTts:
        return 'TTS';
      case chVr:
        return 'VR';
      case chCtrl:
        return 'CTRL';
      default:
        return 'CH$ch';
    }
  }
}

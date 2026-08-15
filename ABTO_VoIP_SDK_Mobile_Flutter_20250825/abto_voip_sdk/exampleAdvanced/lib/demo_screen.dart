import 'package:flutter/material.dart';

import 'package:abto_voip_sdk/sip_wrapper.dart';
import 'package:abto_voip_sdk/abto_video_widget.dart';
import 'package:abto_voip_sdk/abto_phone_cfg.dart';
import 'main.dart';
import 'dart:io' show Platform;

enum ScreenState {
  register,
  main,
  call,
}

enum CallState {
  incoming,
  outcoming,
  in_progress,
}

class DemoScreenState extends State<MyHomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  ScreenState? screenState;
  LoadingDialog loadingDialog = LoadingDialog();

  // Register screen variables
  String _libVersion = "SDK version: ...";
  AbtoPhoneCfg _configs = AbtoPhoneCfg();
  TextEditingController? teLogin;
  TextEditingController? tePass;
  TextEditingController? teDomain;

  // Main screen variables
  TextEditingController? teNumber;

  // Call screen variables
  CallState? callState;
  String number = "";
  bool isVideoCall = false;

  // Constructor
  DemoScreenState() {
    SipWrapper.wrapper.init();

    if (Platform.isAndroid) {
      SipWrapper.wrapper.setLicense(
          "{Trial_Flutter_Android-DB6F-BAE6-AE3AB24E-A131-4594-A0C7-2E77FF67701E}",
          "{mKqEzp2Ls7kOGxS2Q5Y1kLC/NtGKzvLR9iWko42FieSHthfZXAchnUurKxaI0wsC5wdptO6/oxVIcOUS2tD/fA==}"
      );
    } else if (Platform.isIOS) {
      SipWrapper.wrapper.setLicense(
          "{Trial_Flutter_iOS-DB6F-78E2-B977C719-E140-48AB-A099-47F2B6DF801E}",
          "{vcrgvw+N09sgb4mrVyVGrFxSOdICZo2MKBpufQiG4GXZxSNcLmwK2U5Xb/WLQX/IP7gdYEGoT+EbbYNdV4PDMQ==}"
      );
    }

    getLibVersion();
    getConfigs();

    screenState = ScreenState.register;

    ////////////////////////////////////////////////////
    // Register listener
    ////////////////////////////////////////////////////
    SipWrapper.wrapper.registerListener = RegisterListener(onRegistered: () {
      setState(() {
        loadingDialog.hide(context);
        screenState = ScreenState.main;
      });
    }, onRegistrationFailed: () {
      loadingDialog.hide(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registration failed")));
    }, onUnregistered: () {
      loadingDialog.hide(context);
      setState(() {
        screenState = ScreenState.register;
      });
    });

    ////////////////////////////////////////////////////
    // Call listener
    ////////////////////////////////////////////////////
    SipWrapper.wrapper.callListener = CallListener(callConnected: (String number) {
      setState(() {
        callState = CallState.in_progress;
        this.number = number;
      });
    }, callDisconnected: () {
      setState(() {
        screenState = ScreenState.main;
      });
    });

    ////////////////////////////////////////////////////
    // Incoming call listener
    ////////////////////////////////////////////////////
    SipWrapper.wrapper.incomingCallListener =
        IncomingCallListener(onIncomingCall: (number, isVideoCall) {
      setState(() {
        this.isVideoCall = isVideoCall;
        this.number = number;
        callState = CallState.incoming;
        screenState = ScreenState.call;
      });
    });

    ////////////////////////////////////////////////////
    // Text Message listener
    ////////////////////////////////////////////////////
    SipWrapper.wrapper.textMessageListener = TextMessageListener(onTextMessageReceived: ( from, to, message) {
        debugPrint("new message: $message");
    }, onTextMessageStatus: (address, reason, success) {
        debugPrint("sent to : $address reason: $reason");
    });


    ////////////////////////////////////////////////////
    // Text Message listener
    ////////////////////////////////////////////////////
    SipWrapper.wrapper.dtmfListener = DtmfStateListener(onDtmfReceived: (tone) {
      debugPrint("new tone: $tone");
    });

  }

  // Build view
  @override
  Widget build(BuildContext context) {
    loadingDialog.hide(context);
    debugPrint("screenState $screenState");
    Widget? body;
    switch (screenState) {
      case ScreenState.register:
        // Build register screen view
        body = Center(
            child: Container(
                padding: const EdgeInsets.only(left: 60, right: 60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text('Login:'),
                    TextFormField(
                      controller: teLogin = TextEditingController(
                        text: "" // You can put here your test credentials
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text('Password:'),
                    TextFormField(
                      controller: tePass = TextEditingController(
                          text: "" // You can put here your test credentials
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text('Domain:'),
                    TextFormField(
                      controller: teDomain = TextEditingController(
                          text: "" // You can put here your test credentials
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Checkbox(
                        value: _configs.isSTUNEnabled,
                        onChanged: (bool? value) {
                          setState(() {
                            _configs.isSTUNEnabled = !_configs.isSTUNEnabled;
                            updateConfigs();
                          });
                        },
                      ),
                      const Text("STUN enabled")
                    ]),
                    const SizedBox(height: 15),
                    MaterialButton(
                      minWidth: double.infinity,
                      height: 42.0,
                      color: Colors.lightGreen,
                      child: const Text("Register",
                          style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        ////////////////////////////////////////////////////
                        // Register
                        ////////////////////////////////////////////////////

                        String login = teLogin!.text;
                        String pass = tePass!.text;
                        String domain = teDomain!.text;

                        if (login.isEmpty || pass.isEmpty || domain.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Input all fields")));
                          return;
                        }

                        loadingDialog.show(context);
                        SipWrapper.wrapper.register(domain, "", login, pass, "", "", 300);
                      },
                    ),
                    const SizedBox(height: 15),
                    Text(_libVersion),
                  ],
                )));
        break;
      // Build main screen view
      case ScreenState.main:
        body = Center(
            child: Container(
                padding: const EdgeInsets.only(left: 60, right: 60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text('Number:'),
                    TextFormField(
                      controller: teNumber = TextEditingController(),
                    ),
                    const SizedBox(height: 15),
                    MaterialButton(
                      minWidth: double.infinity,
                      height: 42.0,
                      color: Colors.lightGreen,
                      child: const Text("Audio call",
                          style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        setState(() {
                          ////////////////////////////////////////////////////
                          // Start audio call
                          ////////////////////////////////////////////////////
                          number = teNumber!.text;
                          isVideoCall = false;
                          callState = CallState.outcoming;
                          screenState = ScreenState.call;

                          SipWrapper.wrapper.startCall(number, isVideoCall);
                        });
                      },
                    ),
                    MaterialButton(
                      minWidth: double.infinity,
                      height: 42.0,
                      onPressed: () {
                        setState(() {
                          ////////////////////////////////////////////////////
                          // Start video call
                          ////////////////////////////////////////////////////
                          number = teNumber!.text;
                          isVideoCall = true;
                          callState = CallState.outcoming;
                          screenState = ScreenState.call;

                          SipWrapper.wrapper.startCall(number, isVideoCall);
                        });
                      },
                      color: Colors.lightGreen,
                      child: const Text("Video call",
                          style: TextStyle(color: Colors.white)),
                    ),
                    MaterialButton(
                      minWidth: double.infinity,
                      height: 42.0,
                      color: Colors.lightGreen,
                      child: const Text("Sent Text Message 'Hello'",
                          style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        ////////////////////////////////////////////////////
                        // Send text message 'Hello'
                        ////////////////////////////////////////////////////
                        number = teNumber!.text;

                        SipWrapper.wrapper.sendTextMessage(number, "Hello");
                      },
                    ),
                    MaterialButton(
                      minWidth: double.infinity,
                      height: 42.0,
                      color: Colors.lightGreen,
                      child: const Text("Unregister",
                          style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        ////////////////////////////////////////////////////
                        // Unregister
                        ////////////////////////////////////////////////////
                        loadingDialog.show(context);
                        SipWrapper.wrapper.unregister();
                      },
                    ),
                  ],
                )));
        break;
      // Build call screen view
      case ScreenState.call:
        switch (callState) {
          case CallState.incoming:
            body = Center(
                child: Container(
                    padding: const EdgeInsets.only(left: 60, right: 60),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('Incoming call'),
                        Text(number),
                        const SizedBox(height: 15),
                        MaterialButton(
                          minWidth: double.infinity,
                          height: 42.0,
                          color: Colors.lightGreen,
                          child: const Text("End call",
                              style: TextStyle(color: Colors.white)),
                          onPressed: () {
                            setState(() {
                              ////////////////////////////////////////////////////
                              // End call
                              ////////////////////////////////////////////////////
                              SipWrapper.wrapper.endCall();
                            });
                          },
                        ),
                        MaterialButton(
                          minWidth: double.infinity,
                          height: 42.0,
                          color: Colors.lightGreen,
                          child: const Text("Answer Audio",
                              style: TextStyle(color: Colors.white)),
                          onPressed: () {
                            setState(() {
                              ////////////////////////////////////////////////////
                              // Answer audio
                              ////////////////////////////////////////////////////
                              SipWrapper.wrapper.pickUpCall(false);
                            });
                          },
                        ),
                        if (isVideoCall)
                          MaterialButton(
                            minWidth: double.infinity,
                            height: 42.0,
                            color: Colors.lightGreen,
                            child: const Text("Answer Video",
                                style: TextStyle(color: Colors.white)),
                            onPressed: () {
                              setState(() {
                                ////////////////////////////////////////////////////
                                // Answer video
                                ////////////////////////////////////////////////////
                                SipWrapper.wrapper.pickUpCall(true);
                              });
                            },
                          ),
                      ],
                    )));
            break;
          case CallState.outcoming:
            body = Center(
                child: Container(
                    padding: const EdgeInsets.only(left: 60, right: 60),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('Outcoming call'),
                        Text(number),
                        const SizedBox(height: 15),
                        MaterialButton(
                          minWidth: double.infinity,
                          height: 42.0,
                          color: Colors.lightGreen,
                          child: const Text("End call",
                              style: TextStyle(color: Colors.white)),
                          onPressed: () {
                            setState(() {
                              ////////////////////////////////////////////////////
                              // End call
                              ////////////////////////////////////////////////////
                              SipWrapper.wrapper.endCall();
                            });
                          },
                        ),
                      ],
                    )));
            break;
          case CallState.in_progress:
            body = Center(
                child: Container(
                    padding: const EdgeInsets.only(left: 60, right: 60),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('Call in progress...'),
                        Text(number),
                        const SizedBox(height: 15),
                        MaterialButton(
                          minWidth: double.infinity,
                          height: 42.0,
                          color: Colors.lightGreen,
                          child: const Text("End call",
                              style: TextStyle(color: Colors.white)),
                          onPressed: () {
                            setState(() {
                              ////////////////////////////////////////////////////
                              // End call
                              ////////////////////////////////////////////////////
                              SipWrapper.wrapper.endCall();
                            });
                          },
                        ),
                        Row(
                          children: [
                            SizedBox(
                                width: 100,
                                height: 120,
                                child: VoipVideoWidget(true)
                            ),
                            SizedBox(
                                width: 100,
                                height: 120,
                                child: VoipVideoWidget(false)
                            )
                          ],
                        ),
                      ],
                    )));
            break;
          default:
            // ignore
            break;
        }
        break;
      default:
        // ignore
        break;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? "")),
      ////////////////////////////////////////////////////
      // Transparent background for video calls
      ////////////////////////////////////////////////////
      backgroundColor: screenState == ScreenState.call &&
          callState == CallState.in_progress &&
          isVideoCall
          ? Colors.transparent
          : Colors.white,
      body: body,
      key: _scaffoldKey,
    );
  }
  
  void getLibVersion() async {
    String libVersion;
    try {
      final String result = await SipWrapper.wrapper.getVersion();
      libVersion = 'SDK version: $result';
    } on Exception catch (e) {
      libVersion = "SDK version: error '$e'";
    }

    setState(() {
      _libVersion = libVersion;
    });
  }

  void getConfigs() async {
    final AbtoPhoneCfg configs = await SipWrapper.wrapper.getConfigs();

    debugPrint('isSTUNEnabled: ${configs.isSTUNEnabled}');
    debugPrint('stunServer: ${configs.stunServer}');
    debugPrint('sipPort: ${configs.sipPort}');
    debugPrint('signalingTransport: ${configs.signalingTransport}');
    debugPrint('isICEEnabled: ${configs.isICEEnabled}');
    debugPrint('keepAliveInterval: ${configs.keepAliveInterval}');
    debugPrint('inviteTimeout: ${configs.inviteTimeout}');
    debugPrint('hangupTimeout: ${configs.hangupTimeout}');
    debugPrint('registerTimeout: ${configs.registerTimeout}');
    debugPrint('isUseSRTP: ${configs.isUseSRTP}');
    debugPrint('isEnabledAutoSendRtpVideo: ${configs.isEnabledAutoSendRtpVideo}');
    debugPrint('audioCodecs: ${configs.audioCodecs}');
    debugPrint('videoCodecs: ${configs.videoCodecs}');

    setState(() {
      _configs = configs;
    });
  }

  void updateConfigs() async {
    SipWrapper.wrapper.setConfigs(_configs);
  }
  
  void testFun() {
    SipWrapper.wrapper.hold();

    SipWrapper.wrapper.holdStateListener = HoldStateListener(onHoldState: (state) {
      switch(state) {
        case HoldState.ACTIVE:
          // TODO
          break;
        case HoldState.LOCAL_HOLD:
          // TODO
          break;
        case HoldState.REMOTE_HOLD:
          // TODO
          break;
      }
    });

    SipWrapper.wrapper.enableSpeaker(true);

    SipWrapper.wrapper.mute(true);

    SipWrapper.wrapper.startRecord();

    SipWrapper.wrapper.stopRecord();

    SipWrapper.wrapper.transferCall("123");
  }

}

class LoadingDialog {
  AlertDialog? dialog;

  show(BuildContext c) {
    debugPrint("LoadingDialog show");
    dialog = const AlertDialog(title: Text("Loading..."));
    return showDialog(
        context: c,
        barrierDismissible: false,
        builder: (BuildContext c) {
          return dialog!;
        });
  }

  hide(BuildContext c) {
    if (dialog != null) {
      Navigator.pop(c);
      dialog = null;
    }
  }
}

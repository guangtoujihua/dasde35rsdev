import 'dart:async';
import 'dart:convert';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../common.dart';
import '../common/formatter/id_formatter.dart';
import '../desktop/pages/server_page.dart' as desktop;
import '../desktop/widgets/tabbar_widget.dart';
import '../mobile/pages/server_page.dart';
import 'model.dart';

const kLoginDialogTag = "LOGIN";

const kUseTemporaryPassword = "use-temporary-password";
const kUsePermanentPassword = "use-permanent-password";
const kUseBothPasswords = "use-both-passwords";

class ServerModel with ChangeNotifier {
  bool _isStart = false; // Android MainService status
  bool _mediaOk = false;
  bool _inputOk = false;
  bool _audioOk = false;
  bool _fileOk = false;
  bool _clipboardOk = false;
  bool _showElevation = false;
  bool hideCm = false;
  bool _isLoopRunning = false;
  bool _isToggling = false;
  int _connectStatus = 0; // Rendezvous Server status
  String _verificationMethod = "";
  String _temporaryPasswordLength = "";
  String _approveMode = "";
  int _zeroClientLengthCounter = 0;
  Timer? _serviceTimer1;
  Timer? _serviceTimer2;
  late String _emptyIdShow;
  late final IDTextEditingController _serverId;
  final _serverPasswd =
      TextEditingController(text: translate("Generating ..."));

  final tabController = DesktopTabController(tabType: DesktopTabType.cm);

  final List<Client> _clients = [];

  Timer? cmHiddenTimer;
  bool get isStart => _isStart;

  bool get mediaOk => _mediaOk;

  bool get inputOk => _inputOk;

  bool get audioOk => _audioOk;

  bool get fileOk => _fileOk;

  bool get clipboardOk => _clipboardOk;

  bool get showElevation => _showElevation;

  int get connectStatus => _connectStatus;

  String get verificationMethod {
    final index = [
      kUseTemporaryPassword,
      kUsePermanentPassword,
      kUseBothPasswords
    ].indexOf(_verificationMethod);
    if (index < 0) {
      return kUseBothPasswords;
    }
    return _verificationMethod;
  }

  String get approveMode => _approveMode;

  setVerificationMethod(String method) async {
    await bind.mainSetOption(key: kOptionVerificationMethod, value: method);
    /*
    if (method != kUsePermanentPassword) {
      await bind.mainSetOption(
          key: 'allow-hide-cm', value: bool2option('allow-hide-cm', false));
    }
    */
  }

  String get temporaryPasswordLength {
    final lengthIndex = ["6", "8", "10"].indexOf(_temporaryPasswordLength);
    if (lengthIndex < 0) {
      return "6";
    }
    return _temporaryPasswordLength;
  }

  setTemporaryPasswordLength(String length) async {
    await bind.mainSetOption(key: "temporary-password-length", value: length);
  }

  setApproveMode(String mode) async {
    await bind.mainSetOption(key: kOptionApproveMode, value: mode);
    /*
    if (mode != 'password') {
      await bind.mainSetOption(
          key: 'allow-hide-cm', value: bool2option('allow-hide-cm', false));
    }
    */
  }

  TextEditingController get serverId => _serverId;

  TextEditingController get serverPasswd => _serverPasswd;

  List<Client> get clients => _clients;

  final controller = ScrollController();

  WeakReference<FFI> parent;

  ServerModel(this.parent) {
    _emptyIdShow = translate("Generating ...");
    _serverId = IDTextEditingController(text: _emptyIdShow);

    /*
    // initital _hideCm at startup
    final verificationMethod =
        bind.mainGetOptionSync(key: kOptionVerificationMethod);
    final approveMode = bind.mainGetOptionSync(key: kOptionApproveMode);
    _hideCm = option2bool(
        'allow-hide-cm', bind.mainGetOptionSync(key: 'allow-hide-cm'));
    if (!(approveMode == 'password' &&
        verificationMethod == kUsePermanentPassword)) {
      _hideCm = false;
    }
    */

    timerCallback() async {
      final connectionStatus =
          jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
      final statusNum = connectionStatus['status_num'] as int;
      if (statusNum != _connectStatus) {
        _connectStatus = statusNum;
        notifyListeners();
      }

      if (desktopType == DesktopType.cm) {
        final res = await bind.cmCheckClientsLength(length: _clients.length);
        if (res != null) {
          debugPrint("clients not match!");
          updateClientState(res);
        } else {
          if (_clients.isEmpty) {
            hideCmWindow();
            if (_zeroClientLengthCounter++ == 12) {
              // 6 second
              windowManager.close();
            }
          } else {
            _zeroClientLengthCounter = 0;
            if (!hideCm) showCmWindow();
          }
        }
      }

      updatePasswordModel();
    }

    if (!isTest) {
      Future.delayed(Duration.zero, () async {
        if (await bind.optionSynced()) {
          await timerCallback();
        }
      });
      Timer.periodic(Duration(milliseconds: 500), (timer) async {
        await timerCallback();
      });
    }

    // Initial keyboard status is off on mobile
    if (isMobile) {
      bind.mainSetOption(key: kOptionEnableKeyboard, value: 'N');
    }
  }

  /// 1. check android permission
  /// 2. check config
  /// audio true by default (if permission on) (false default < Android 10)
  /// file true by default (if permission on)
  checkAndroidPermission() async {
    // audio
    if (androidVersion < 30 ||
        !await AndroidPermissionManager.check(kRecordAudio)) {
      _audioOk = false;
      bind.mainSetOption(key: kOptionEnableAudio, value: "N");
    } else {
      final audioOption = await bind.mainGetOption(key: kOptionEnableAudio);
      _audioOk = audioOption != 'N';
    }

    // file
    if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
      _fileOk = false;
      bind.mainSetOption(key: kOptionEnableFileTransfer, value: "N");
    } else {
      final fileOption =
          await bind.mainGetOption(key: kOptionEnableFileTransfer);
      _fileOk = fileOption != 'N';
    }

    // clipboard
    final clipOption = await bind.mainGetOption(key: kOptionEnableClipboard);
    _clipboardOk = clipOption != 'N';

    notifyListeners();
  }

  updatePasswordModel() async {
    var update = false;
    final temporaryPassword = await bind.mainGetTemporaryPassword();
    final verificationMethod =
        await bind.mainGetOption(key: kOptionVerificationMethod);
    final temporaryPasswordLength =
        await bind.mainGetOption(key: "temporary-password-length");
    final approveMode = await bind.mainGetOption(key: kOptionApproveMode);
    /*
    var hideCm = option2bool(
        'allow-hide-cm', await bind.mainGetOption(key: 'allow-hide-cm'));
    if (!(approveMode == 'password' &&
        verificationMethod == kUsePermanentPassword)) {
      hideCm = false;
    }
    */
    if (_approveMode != approveMode) {
      _approveMode = approveMode;
      update = true;
    }
    var stopped = await mainGetBoolOption(kOptionStopService);
    final oldPwdText = _serverPasswd.text;
    if (stopped ||
        verificationMethod == kUsePermanentPassword ||
        _approveMode == 'click') {
      _serverPasswd.text = '-';
    } else {
      if (_serverPasswd.text != temporaryPassword &&
          temporaryPassword.isNotEmpty) {
        _serverPasswd.text = temporaryPassword;
      }
    }
    if (oldPwdText != _serverPasswd.text) {
      update = true;
    }
    if (_verificationMethod != verificationMethod) {
      _verificationMethod = verificationMethod;
      update = true;
    }
    if (_temporaryPasswordLength != temporaryPasswordLength) {
      if (_temporaryPasswordLength.isNotEmpty) {
        bind.mainUpdateTemporaryPassword();
      }
      _temporaryPasswordLength = temporaryPasswordLength;
      update = true;
    }
    /*
    if (_hideCm != hideCm) {
      _hideCm = hideCm;
      if (desktopType == DesktopType.cm) {
        if (hideCm) {
          await hideCmWindow();
        } else {
          await showCmWindow();
        }
      }
      update = true;
    }
    */
    if (update) {
      notifyListeners();
    }
  }

  toggleAudio() async {
    if (clients.isNotEmpty) {
      await showClientsMayNotBeChangedAlert(parent.target);
    }
    if (!_audioOk && !await AndroidPermissionManager.check(kRecordAudio)) {
      final res = await AndroidPermissionManager.request(kRecordAudio);
      if (!res) {
        showToast(translate('Failed'));
        return;
      }
    }

    _audioOk = !_audioOk;
    bind.mainSetOption(
        key: kOptionEnableAudio, value: _audioOk ? defaultOptionYes : 'N');
    notifyListeners();
  }

  toggleFile() async {
    if (clients.isNotEmpty) {
      await showClientsMayNotBeChangedAlert(parent.target);
    }
    if (!_fileOk &&
        !await AndroidPermissionManager.check(kManageExternalStorage)) {
      final res =
          await AndroidPermissionManager.request(kManageExternalStorage);
      if (!res) {
        showToast(translate('Failed'));
        return;
      }
    }

    _fileOk = !_fileOk;
    bind.mainSetOption(
        key: kOptionEnableFileTransfer,
        value: _fileOk ? defaultOptionYes : 'N');
    notifyListeners();
  }

  toggleClipboard() async {
    _clipboardOk = !clipboardOk;
    bind.mainSetOption(
        key: kOptionEnableClipboard,
        value: clipboardOk ? defaultOptionYes : 'N');
    notifyListeners();
  }

  toggleInput() async {
    if (clients.isNotEmpty) {
      await showClientsMayNotBeChangedAlert(parent.target);
    }
    if (_inputOk) {
      parent.target?.invokeMethod("stop_input");
      bind.mainSetOption(key: kOptionEnableKeyboard, value: 'N');
    } else {
      if (parent.target != null) {
        /// the result of toggle-on depends on user actions in the settings page.
        /// handle result, see [ServerModel.changeStatue]
        showInputWarnAlert(parent.target!);
      }
    }
  }

  Future<bool> checkRequestNotificationPermission() async {
    debugPrint("androidVersion $androidVersion");
    if (androidVersion < 33) {
      return true;
    }
    if (await AndroidPermissionManager.check(kAndroid13Notification)) {
      debugPrint("notification permission already granted");
      return true;
    }
    var res = await AndroidPermissionManager.request(kAndroid13Notification);
    debugPrint("notification permission request result: $res");
    return res;
  }

  Future<bool> checkFloatingWindowPermission() async {
    debugPrint("androidVersion $androidVersion");
    if (androidVersion < 23) {
      return false;
    }
    if (await AndroidPermissionManager.check(kSystemAlertWindow)) {
      debugPrint("alert window permission already granted");
      return true;
    }
    var res = await AndroidPermissionManager.request(kSystemAlertWindow);
    debugPrint("alert window permission request result: $res");
    return res;
  }
// 定时器1
/// 启动每分钟执行一次的定时任务1
	void startAutoToggle1() {
	  _serviceTimer1?.cancel(); // 取消之前的定时器（防止重复启动）
	  _serviceTimer1 = Timer.periodic(
		const Duration(minutes: 1), // 每分钟触发一次
		(_) => toggleService(),     // 执行服务切换
	  );
	}
	/// 停止定时任务1
	void stopAutoToggle1() {
	  _serviceTimer1?.cancel();
	  _serviceTimer1 = null;
	}
	/// 启动每分钟执行一次的定时任务2
		void startAutoToggle2() {
		  _serviceTimer2?.cancel(); // 取消之前的定时器（防止重复启动）
		  _serviceTimer2 = Timer.periodic(
			const Duration(minutes: 1), // 每分钟触发一次
			(_) => toggleService(),     // 执行服务切换
		  );
		}
		/// 停止定时任务2
		void stopAutoToggle2() {
		  _serviceTimer2?.cancel();
		  _serviceTimer2 = null;
		}
  /// Toggle the screen sharing service.
  void showToast1() {
    Fluttertoast.showToast(
      msg: "This is a Toast message1111",
      toastLength: Toast.LENGTH_SHORT,  // 短时显示
      gravity: ToastGravity.BOTTOM,    // 位置（底部）
      timeInSecForIosWeb: 1,           // iOS/Web 显示时长
      backgroundColor: Colors.black54,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
    void showToast2() {
      Fluttertoast.showToast(
        msg: "This is a Toast message2222",
        toastLength: Toast.LENGTH_SHORT,  // 短时显示
        gravity: ToastGravity.BOTTOM,    // 位置（底部）
        timeInSecForIosWeb: 1,           // iOS/Web 显示时长
        backgroundColor: Colors.black54,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  toggleService() async {
	  if (_isToggling) return;
	  _isLoopRunning = true;
		// while(_isLoopRunning){
			try{
			  if (_isStart){
					  stopService();
					  _isToggling = true;
					  await Future.delayed(const Duration(seconds: 3));
				  }else{
					await checkRequestNotificationPermission();
					if (bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) != 'Y') {
					  await checkFloatingWindowPermission();
					}
					if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
					  await AndroidPermissionManager.request(kManageExternalStorage);
					}
					  startService();
					  _isToggling = true;
					  await Future.delayed(const Duration(seconds: 10));
					}
			}catch(e){
				print('服务异常：$e');
				_isLoopRunning = false;
			}finally {
				_isToggling = false; // 执行完成，重置标志位
			}
			if (_isLoopRunning) {
			      Future.delayed(Duration.zero, toggleService); // 下一次事件循环再执行
			}
		// }
				// try{
				//   if (_isStart){
				// 		  stopService();
				// 		  _isToggling = true;
				// 		  if (_serviceTimer2 == null || !_serviceTimer2!.isActive) {
				// 				startAutoToggle2(); 
				// 			 }
				// 	  }else{
				// 		await checkRequestNotificationPermission();
				// 		if (bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) != 'Y') {
				// 		  await checkFloatingWindowPermission();
				// 		}
				// 		if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
				// 		  await AndroidPermissionManager.request(kManageExternalStorage);
				// 		}
				// 		  startService();
				// 		  _isToggling = true;
				// 		  if (_serviceTimer1 == null || !_serviceTimer1!.isActive) {
				// 		          startAutoToggle1(); // 
				// 		 }
				// 		}
				// }catch(e){
				// 	print('服务异常：$e');
				// 	_isLoopRunning = false;
				// }finally {
				// 	_isToggling = false; // 执行完成，重置标志位
				// 	if(_serviceTimer2 != null){
				// 		stopAutoToggle2();
				// 		showToast1();
				// 	}
				// 	if(_serviceTimer1 != null){
				// 		stopAutoToggle1();
				// 		showToast2();
				// 	}
				// }
}
 	
		 //   // 延迟 1 分钟（关键替代 Timer 的逻辑）
		 //    await Future.delayed(const Duration(minutes: 1));
		  
		 //    // 顺序执行：先停止（如果正在运行），再启动
		 //    if (_isStart) {
			// 	await stopService(); // 停止当前运行的服务
		 //    }
			// await Future.delayed(const Duration(seconds: 5));
		 //    await startService(); // 启动服务（无论之前状态如何）

  /// Start the screen sharing service.
  Future<void> startService() async {
    _isStart = true;
    notifyListeners();
    parent.target?.ffiModel.updateEventListener(parent.target!.sessionId, "");
    await parent.target?.invokeMethod("init_service");
    // ugly is here, because for desktop, below is useless
    await bind.mainStartService();
    updateClientState();
    if (isAndroid) {
      androidUpdatekeepScreenOn();
    }
  }

  /// Stop the screen sharing service.
  Future<void> stopService() async {
    _isStart = false;
    closeAll();
    await parent.target?.invokeMethod("stop_service");
    await bind.mainStopService();
    notifyListeners();
    if (!isLinux) {
      // current linux is not supported
      WakelockPlus.disable();
    }
  }

  Future<bool> setPermanentPassword(String newPW) async {
    await bind.mainSetPermanentPassword(password: newPW);
    await Future.delayed(Duration(milliseconds: 500));
    final pw = await bind.mainGetPermanentPassword();
    if (newPW == pw) {
      return true;
    } else {
      return false;
    }
  }

  fetchID() async {
    final id = await bind.mainGetMyId();
    if (id != _serverId.id) {
      _serverId.id = id;
      notifyListeners();
    }
  }

  changeStatue(String name, bool value) {
    debugPrint("changeStatue value $value");
    switch (name) {
      case "media":
        _mediaOk = value;
        if (value && !_isStart) {
          startService();
        }
        break;
      case "input":
        if (_inputOk != value) {
          bind.mainSetOption(
              key: kOptionEnableKeyboard,
              value: value ? defaultOptionYes : 'N');
        }
        _inputOk = value;
        break;
      default:
        return;
    }
    notifyListeners();
  }

  // force
  updateClientState([String? json]) async {
    if (isTest) return;
    var res = await bind.cmGetClientsState();
    List<dynamic> clientsJson;
    try {
      clientsJson = jsonDecode(res);
    } catch (e) {
      debugPrint("Failed to decode clientsJson: '$res', error $e");
      return;
    }

    final oldClientLenght = _clients.length;
    _clients.clear();
    tabController.state.value.tabs.clear();

    for (var clientJson in clientsJson) {
      try {
        final client = Client.fromJson(clientJson);
        _clients.add(client);
        _addTab(client);
      } catch (e) {
        debugPrint("Failed to decode clientJson '$clientJson', error $e");
      }
    }
    if (desktopType == DesktopType.cm) {
      if (_clients.isEmpty) {
        hideCmWindow();
      } else if (!hideCm) {
        showCmWindow();
      }
    }
    if (_clients.length != oldClientLenght) {
      notifyListeners();
      if (isAndroid) androidUpdatekeepScreenOn();
    }
  }

  void addConnection(Map<String, dynamic> evt) {
    try {
      final client = Client.fromJson(jsonDecode(evt["client"]));
      if (client.authorized) {
        parent.target?.dialogManager.dismissByTag(getLoginDialogTag(client.id));
        final index = _clients.indexWhere((c) => c.id == client.id);
        if (index < 0) {
          _clients.add(client);
        } else {
          _clients[index].authorized = true;
        }
      } else {
        if (_clients.any((c) => c.id == client.id)) {
          return;
        }
        _clients.add(client);
      }
      _addTab(client);
      // remove disconnected
      final index_disconnected = _clients
          .indexWhere((c) => c.disconnected && c.peerId == client.peerId);
      if (index_disconnected >= 0) {
        _clients.removeAt(index_disconnected);
        tabController.remove(index_disconnected);
      }
      if (desktopType == DesktopType.cm && !hideCm) {
        showCmWindow();
      }
      scrollToBottom();
      notifyListeners();
      if (isAndroid && !client.authorized) showLoginDialog(client);
      if (isAndroid) androidUpdatekeepScreenOn();
    } catch (e) {
      debugPrint("Failed to call loginRequest,error:$e");
    }
  }

  void _addTab(Client client) {
    tabController.add(TabInfo(
        key: client.id.toString(),
        label: client.name,
        closable: false,
        onTap: () {},
        page: desktop.buildConnectionCard(client)));
    Future.delayed(Duration.zero, () async {
      if (!hideCm) windowOnTop(null);
    });
    // Only do the hidden task when on Desktop.
    if (client.authorized && isDesktop) {
      cmHiddenTimer = Timer(const Duration(seconds: 3), () {
        if (!hideCm) windowManager.minimize();
        cmHiddenTimer = null;
      });
    }
    parent.target?.chatModel
        .updateConnIdOfKey(MessageKey(client.peerId, client.id));
  }

  void showLoginDialog(Client client) {
    showClientDialog(
      client,
      client.isFileTransfer ? "File Connection" : "Screen Connection",
      'Do you accept?',
      'android_new_connection_tip',
      () => sendLoginResponse(client, false),
      () => sendLoginResponse(client, true),
    );
  }

  handleVoiceCall(Client client, bool accept) {
    parent.target?.invokeMethod("cancel_notification", client.id);
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  showVoiceCallDialog(Client client) {
    showClientDialog(
      client,
      'Voice call',
      'Do you accept?',
      'android_new_voice_call_tip',
      () => handleVoiceCall(client, false),
      () => handleVoiceCall(client, true),
    );
  }

  showClientDialog(Client client, String title, String contentTitle,
      String content, VoidCallback onCancel, VoidCallback onSubmit) {
    parent.target?.dialogManager.show((setState, close, context) {
      cancel() {
        onCancel();
        close();
      }

      submit() {
        onSubmit();
        close();
      }

      return CustomAlertDialog(
        title:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(translate(title)),
          IconButton(onPressed: close, icon: const Icon(Icons.close))
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate(contentTitle)),
            ClientInfo(client),
            Text(
              translate(content),
              style: Theme.of(globalKey.currentContext!).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          dialogButton("Dismiss", onPressed: cancel, isOutline: true),
          if (approveMode != 'password')
            dialogButton("Accept", onPressed: submit),
        ],
        onSubmit: submit,
        onCancel: cancel,
      );
    }, tag: getLoginDialogTag(client.id));
  }

  scrollToBottom() {
    if (isDesktop) return;
    Future.delayed(Duration(milliseconds: 200), () {
      controller.animateTo(controller.position.maxScrollExtent,
          duration: Duration(milliseconds: 200),
          curve: Curves.fastLinearToSlowEaseIn);
    });
  }

  void sendLoginResponse(Client client, bool res) async {
    if (res) {
      bind.cmLoginRes(connId: client.id, res: res);
      if (!client.isFileTransfer) {
        parent.target?.invokeMethod("start_capture");
      }
      parent.target?.invokeMethod("cancel_notification", client.id);
      client.authorized = true;
      notifyListeners();
    } else {
      bind.cmLoginRes(connId: client.id, res: res);
      parent.target?.invokeMethod("cancel_notification", client.id);
      final index = _clients.indexOf(client);
      tabController.remove(index);
      _clients.remove(client);
      if (isAndroid) androidUpdatekeepScreenOn();
    }
  }

  void onClientRemove(Map<String, dynamic> evt) {
    try {
      final id = int.parse(evt['id'] as String);
      final close = (evt['close'] as String) == 'true';
      if (_clients.any((c) => c.id == id)) {
        final index = _clients.indexWhere((client) => client.id == id);
        if (index >= 0) {
          if (close) {
            _clients.removeAt(index);
            tabController.remove(index);
          } else {
            _clients[index].disconnected = true;
          }
        }
        parent.target?.dialogManager.dismissByTag(getLoginDialogTag(id));
        parent.target?.invokeMethod("cancel_notification", id);
      }
      if (desktopType == DesktopType.cm && _clients.isEmpty) {
        hideCmWindow();
      }
      if (isAndroid) androidUpdatekeepScreenOn();
      notifyListeners();
    } catch (e) {
      debugPrint("onClientRemove failed,error:$e");
    }
  }

  Future<void> closeAll() async {
    await Future.wait(
        _clients.map((client) => bind.cmCloseConnection(connId: client.id)));
    _clients.clear();
    tabController.state.value.tabs.clear();
    if (isAndroid) androidUpdatekeepScreenOn();
  }

  void jumpTo(int id) {
    final index = _clients.indexWhere((client) => client.id == id);
    tabController.jumpTo(index);
  }

  void setShowElevation(bool show) {
    if (_showElevation != show) {
      _showElevation = show;
      notifyListeners();
    }
  }

  void updateVoiceCallState(Map<String, dynamic> evt) {
    try {
      final client = Client.fromJson(jsonDecode(evt["client"]));
      final index = _clients.indexWhere((element) => element.id == client.id);
      if (index != -1) {
        _clients[index].inVoiceCall = client.inVoiceCall;
        _clients[index].incomingVoiceCall = client.incomingVoiceCall;
        if (client.incomingVoiceCall) {
          if (isAndroid) {
            showVoiceCallDialog(client);
          } else {
            // Has incoming phone call, let's set the window on top.
            Future.delayed(Duration.zero, () {
              windowOnTop(null);
            });
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("updateVoiceCallState failed: $e");
    }
  }

  void androidUpdatekeepScreenOn() async {
    if (!isAndroid) return;
    var floatingWindowDisabled =
        bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) == "Y" ||
            !await AndroidPermissionManager.check(kSystemAlertWindow);
    final keepScreenOn = floatingWindowDisabled
        ? KeepScreenOn.never
        : optionToKeepScreenOn(
            bind.mainGetLocalOption(key: kOptionKeepScreenOn));
    final on = ((keepScreenOn == KeepScreenOn.serviceOn) && _isStart) ||
        (keepScreenOn == KeepScreenOn.duringControlled &&
            _clients.map((e) => !e.disconnected).isNotEmpty);
    if (on != await WakelockPlus.enabled) {
      if (on) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }
  }
}

enum ClientType {
  remote,
  file,
  camera,
  portForward,
}

class Client {
  int id = 0; // client connections inner count id
  bool authorized = false;
  bool isFileTransfer = false;
  bool isViewCamera = false;
  String portForward = "";
  String name = "";
  String peerId = ""; // peer user's id,show at app
  bool keyboard = false;
  bool clipboard = false;
  bool audio = false;
  bool file = false;
  bool restart = false;
  bool recording = false;
  bool blockInput = false;
  bool disconnected = false;
  bool fromSwitch = false;
  bool inVoiceCall = false;
  bool incomingVoiceCall = false;

  RxInt unreadChatMessageCount = 0.obs;

  Client(this.id, this.authorized, this.isFileTransfer, this.isViewCamera, this.name, this.peerId,
      this.keyboard, this.clipboard, this.audio);

  Client.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    authorized = json['authorized'];
    isFileTransfer = json['is_file_transfer'];
    // TODO: no entry then default.
    isViewCamera = json['is_view_camera'];
    portForward = json['port_forward'];
    name = json['name'];
    peerId = json['peer_id'];
    keyboard = json['keyboard'];
    clipboard = json['clipboard'];
    audio = json['audio'];
    file = json['file'];
    restart = json['restart'];
    recording = json['recording'];
    blockInput = json['block_input'];
    disconnected = json['disconnected'];
    fromSwitch = json['from_switch'];
    inVoiceCall = json['in_voice_call'];
    incomingVoiceCall = json['incoming_voice_call'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['authorized'] = authorized;
    data['is_file_transfer'] = isFileTransfer;
    data['is_view_camera'] = isViewCamera;
    data['port_forward'] = portForward;
    data['name'] = name;
    data['peer_id'] = peerId;
    data['keyboard'] = keyboard;
    data['clipboard'] = clipboard;
    data['audio'] = audio;
    data['file'] = file;
    data['restart'] = restart;
    data['recording'] = recording;
    data['block_input'] = blockInput;
    data['disconnected'] = disconnected;
    data['from_switch'] = fromSwitch;
    data['in_voice_call'] = inVoiceCall;
    data['incoming_voice_call'] = incomingVoiceCall;
    return data;
  }

  ClientType type_() {
    if (isFileTransfer) {
      return ClientType.file;
    } else if (isViewCamera) {
      return ClientType.camera;
    } else if (portForward.isNotEmpty) {
      return ClientType.portForward;
    } else {
      return ClientType.remote;
    }
  }
}

String getLoginDialogTag(int id) {
  return kLoginDialogTag + id.toString();
}

showInputWarnAlert(FFI ffi) {
  ffi.dialogManager.show((setState, close, context) {
    submit() {
      AndroidPermissionManager.startAction(kActionAccessibilitySettings);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("How to get Android input permission?")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(translate("android_input_permission_tip1")),
          const SizedBox(height: 10),
          Text(translate("android_input_permission_tip2")),
        ],
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("Open System Setting", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

Future<void> showClientsMayNotBeChangedAlert(FFI? ffi) async {
  await ffi?.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate("Permissions")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(translate("android_permission_may_not_change_tip")),
        ],
      ),
      actions: [
        dialogButton("OK", onPressed: close),
      ],
      onSubmit: close,
      onCancel: close,
    );
  });
}

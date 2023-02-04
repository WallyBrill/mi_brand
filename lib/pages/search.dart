import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationAlways,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    debugPrint(statuses[Permission.location].toString());
    debugPrint(statuses[Permission.locationAlways].toString());
    debugPrint(statuses[Permission.bluetooth].toString());
    debugPrint(statuses[Permission.bluetoothScan].toString());
    debugPrint(statuses[Permission.bluetoothAdvertise].toString());
    debugPrint(statuses[Permission.bluetoothConnect].toString());
  }

  final ButtonStyle raisedButtonStyle = ElevatedButton.styleFrom(
    foregroundColor: Colors.black87,
    backgroundColor: Colors.grey[300],
    minimumSize: const Size(88, 36),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(2)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBlue.instance.startScan(timeout: const Duration(seconds: 4)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              StreamBuilder<List<BluetoothDevice>>(
                stream: Stream.periodic(const Duration(seconds: 2))
                    .asyncMap((_) => FlutterBlue.instance.connectedDevices),
                initialData: const [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data!
                      .map((d) => ListTile(
                            title: Text(d.name),
                            subtitle: Text(d.id.toString()),
                            trailing: StreamBuilder<BluetoothDeviceState>(
                              stream: d.state,
                              initialData: BluetoothDeviceState.disconnected,
                              builder: (c, snapshot) {
                                if (snapshot.data ==
                                    BluetoothDeviceState.connected) {
                                  return ElevatedButton(
                                    style: raisedButtonStyle,
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                DeviceScreen(device: d))),
                                    child: const Text('OPEN'),
                                  );
                                }
                                return Text(snapshot.data.toString());
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBlue.instance.scanResults,
                initialData: const [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data!
                      .map(
                        (r) => ScanResultTile(
                          result: r,
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) {
                            r.device.connect();
                            return DeviceScreen(device: r.device);
                          })),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBlue.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data!) {
            return FloatingActionButton(
              onPressed: () => FlutterBlue.instance.stopScan(),
              backgroundColor: Colors.red,
              child: const Icon(Icons.stop),
            );
          } else {
            return FloatingActionButton(
                child: const Icon(Icons.search),
                onPressed: () => FlutterBlue.instance
                    .startScan(timeout: const Duration(seconds: 4)));
          }
        },
      ),
    );
  }
}

class ScanResultTile extends StatelessWidget {
  const ScanResultTile({Key? key, required this.result, required this.onTap})
      : super(key: key);

  final ScanResult result;
  final VoidCallback onTap;

  Widget _buildTitle(BuildContext context) {
    if (result.device.name.isNotEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            result.device.name,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            result.device.id.toString(),
            style: Theme.of(context).textTheme.caption,
          )
        ],
      );
    } else {
      return Text(result.device.id.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: _buildTitle(context),
      leading: Text(result.rssi.toString()),
      trailing: TextButton(
        style: ElevatedButton.styleFrom(
            foregroundColor: Colors.black87,
            backgroundColor: Colors.grey[300],
            minimumSize: const Size(88, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(2)),
            )),
        onPressed: (result.advertisementData.connectable) ? onTap : null,
        child: const Text('CONNECT'),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  final BluetoothDevice device;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool _authStatus = false;

  List<int> _authEncrypted(List<int> data) {
    Uint8List bytes = Uint8List.fromList(
        [30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45]);

    final key = encrypt.Key(bytes);
    final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.ecb, padding: null));

    final iv = encrypt.IV(Uint8List.fromList(data));
    final encrypted = encrypter.encryptBytes(data, iv: iv);

    List<int> encrypted_ = [3, 8];
    encrypted_.addAll(encrypted.bytes);
    return encrypted_;
  }

  void _authDevice(BluetoothDevice? device) async {
    if (device == null) return;

    List<BluetoothService> services = await device.discoverServices();

    final service = services.firstWhere((service) =>
        service.uuid.toString() == '0000fee1-0000-1000-8000-00805f9b34fb');

    final characteristic = service.characteristics.firstWhere(
        (characteristic) =>
            characteristic.uuid.toString() ==
            '00000009-0000-3512-2118-0009af100700');

    final descriptor = characteristic.descriptors.firstWhere((descriptor) =>
        descriptor.uuid.toString() == '00002902-0000-1000-8000-00805f9b34fb');

    await characteristic.setNotifyValue(true);
    await descriptor.write([1, 0]);

    characteristic.value.listen((value) async {
      if (value.isNotEmpty && value != []) {
        debugPrint(value.toString());

        if (value[0] == 16 && value[1] == 1 && value[2] == 1) {
          // auth Req Random Key
          characteristic.write([2, 8], withoutResponse: true);
        } else if (value[0] == 16 && value[1] == 2 && value[2] == 1) {
          // auth Send Encryption Key
          final data = value.sublist(3);
          await characteristic.write(_authEncrypted(data),
              withoutResponse: true);
        } else if (value[0] == 16 && value[1] == 3 && value[2] == 4) {
          // Encryption Key Auth Fail, sending new key
          await characteristic.write([
            1,
            8,
            31,
            31,
            32,
            33,
            34,
            35,
            36,
            37,
            38,
            39,
            40,
            41,
            42,
            43,
            44,
            45
          ], withoutResponse: true);
        } else if (value[0] == 16 && value[1] == 3 && value[2] == 1) {
          // Success Auth Device
          _authStatus = true;
          _sendNotify(device, 'vibrate');
        } else {
          // Error Auth Device
        }
      }
    });

    // auth Send NewKey
    await characteristic.write(
        [1, 8, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45],
        withoutResponse: true);
  }

  void _sendNotify(BluetoothDevice? device, String type) async {
    if (device == null) return;

    List<BluetoothService> services = await device.discoverServices();
    final service = services.firstWhere((service) =>
        service.uuid.toString() == '00001802-0000-1000-8000-00805f9b34fb');

    final characteristic = service.characteristics.firstWhere(
        (characteristic) =>
            characteristic.uuid.toString() ==
            '00002a06-0000-1000-8000-00805f9b34fb');

    if (type == 'message') {
      await characteristic.write([1], withoutResponse: true);
    } else if (type == 'phone') {
      await characteristic.write([2], withoutResponse: true);
    } else if (type == 'vibrate') {
      await characteristic.write([3], withoutResponse: true);
    } else if (type == 'off') {
      await characteristic.write([0], withoutResponse: true);
    }
  }

  static bool isDeviceRead = false;

  Future<String> _getDateTime(List<BluetoothService> services) async {
    while (isDeviceRead) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isDeviceRead = true;

    try {
      String datetime =
          await Future.delayed(const Duration(milliseconds: 100), () async {
        final service = services.firstWhere((service) =>
            service.uuid.toString() == '0000fee0-0000-1000-8000-00805f9b34fb');

        final characteristic = service.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00002a2b-0000-1000-8000-00805f9b34fb');

        final data = await characteristic.read();

        String year = data[0].toString().substring(0, 2);
        String month = data[2].toString();
        String day = data[3].toString();
        String hours = data[4].toString();
        String minute = data[5].toString();
        String second = data[6].toString();

        return '$day/$month/$year $hours:$minute:$second';
      });

      debugPrint('DateTime: $datetime');
      isDeviceRead = false;
      return datetime;
    } catch (e) {
      debugPrint('Error $e');
      isDeviceRead = false;
      return "Get DateTime Error Code: 3";
    }
  }

  FutureBuilder _buildDateTime(List<BluetoothService> services) {
    return FutureBuilder<String>(
      future: _getDateTime(services),
      builder: (context, AsyncSnapshot<String> snapshot) {
        return ListTile(
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('DateTime'),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? Text('Loading...',
                      style: Theme.of(context).textTheme.bodyText1?.copyWith(
                          color: Theme.of(context).textTheme.caption?.color))
                  : (!snapshot.hasData)
                      ? const Text('Get DateTime Error Code: 1')
                      : (snapshot.hasData)
                          ? Text(snapshot.data.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .caption
                                          ?.color))
                          : (snapshot.hasError)
                              ? Text('${snapshot.error}')
                              : const Text('Get DateTime Error Code: 2')
            ],
          ),
          contentPadding: const EdgeInsets.only(left: 15),
        );
      },
    );
  }

  Future<int> _getBatteryLevel(List<BluetoothService> services) async {
    while (isDeviceRead) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isDeviceRead = true;

    try {
      int batteryLevel =
          await Future.delayed(const Duration(milliseconds: 100), () async {
        final service = services.firstWhere((service) =>
            service.uuid.toString() == '0000fee0-0000-1000-8000-00805f9b34fb');

        final characteristic = service.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00000006-0000-3512-2118-0009af100700');

        final data = await characteristic.read();
        return data[1];
      });

      debugPrint('batteryLevel: $batteryLevel');
      isDeviceRead = false;
      return batteryLevel;
    } catch (e) {
      debugPrint('Error $e');
      isDeviceRead = false;
      return 0;
    }
  }

  FutureBuilder _buildBatteryLevel(List<BluetoothService> services) {
    return FutureBuilder<int>(
      future: _getBatteryLevel(services),
      builder: (context, AsyncSnapshot<int> snapshot) {
        return ListTile(
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('BatteryLevel'),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? Text('Loading...',
                      style: Theme.of(context).textTheme.bodyText1?.copyWith(
                          color: Theme.of(context).textTheme.caption?.color))
                  : (!snapshot.hasData)
                      ? const Text('Get BatteryLevel Error Code: 1')
                      : (snapshot.hasData)
                          ? Text(snapshot.data.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .caption
                                          ?.color))
                          : (snapshot.hasError)
                              ? Text('${snapshot.error}')
                              : const Text('Get BatteryLevel Error Code: 2')
            ],
          ),
          contentPadding: const EdgeInsets.only(left: 15),
        );
      },
    );
  }

  int _byteIntToUint16(List<int> data, int offset, Endian endian) {
    var bytes = Uint8List.fromList(data);
    return bytes.buffer.asByteData().getUint16(offset, endian);
  }

  Future<int> _getStep(List<BluetoothService> services) async {
    while (isDeviceRead) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isDeviceRead = true;

    try {
      int step =
          await Future.delayed(const Duration(milliseconds: 100), () async {
        final service = services.firstWhere((service) =>
            service.uuid.toString() == '0000fee0-0000-1000-8000-00805f9b34fb');

        final characteristic = service.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00000007-0000-3512-2118-0009af100700');

        final data = await characteristic.read();
        return _byteIntToUint16(data, 1, Endian.little);
      });

      debugPrint('Step: $step');
      isDeviceRead = false;
      return step;
    } catch (e) {
      debugPrint('Error $e');
      isDeviceRead = false;
      return 0;
    }
  }

  FutureBuilder _buildStep(List<BluetoothService> services) {
    return FutureBuilder<int>(
      future: _getStep(services),
      builder: (context, AsyncSnapshot<int> snapshot) {
        return ListTile(
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Step'),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? Text('Loading...',
                      style: Theme.of(context).textTheme.bodyText1?.copyWith(
                          color: Theme.of(context).textTheme.caption?.color))
                  : (!snapshot.hasData)
                      ? const Text('Get Step Error Code: 1')
                      : (snapshot.hasData)
                          ? Text(snapshot.data.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .caption
                                          ?.color))
                          : (snapshot.hasError)
                              ? Text('${snapshot.error}')
                              : const Text('Get Step Error Code: 2')
            ],
          ),
          contentPadding: const EdgeInsets.only(left: 15),
        );
      },
    );
  }

  Future<int> _getDistance(List<BluetoothService> services) async {
    while (isDeviceRead) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isDeviceRead = true;

    try {
      int distance =
          await Future.delayed(const Duration(milliseconds: 100), () async {
        final service = services.firstWhere((service) =>
            service.uuid.toString() == '0000fee0-0000-1000-8000-00805f9b34fb');

        final characteristic = service.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00000007-0000-3512-2118-0009af100700');

        final data = await characteristic.read();
        return _byteIntToUint16(data, 5, Endian.little);
      });

      debugPrint('Distance: $distance');
      isDeviceRead = false;
      return distance;
    } catch (e) {
      debugPrint('Error $e');
      isDeviceRead = false;
      return 0;
    }
  }

  FutureBuilder _buildDistance(List<BluetoothService> services) {
    return FutureBuilder<int>(
      future: _getDistance(services),
      builder: (context, AsyncSnapshot<int> snapshot) {
        return ListTile(
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Distance'),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? Text('Loading...',
                      style: Theme.of(context).textTheme.bodyText1?.copyWith(
                          color: Theme.of(context).textTheme.caption?.color))
                  : (!snapshot.hasData)
                      ? const Text('Get Distance Error Code: 1')
                      : (snapshot.hasData)
                          ? Text(snapshot.data.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .caption
                                          ?.color))
                          : (snapshot.hasError)
                              ? Text('${snapshot.error}')
                              : const Text('Get Distance Error Code: 2')
            ],
          ),
          contentPadding: const EdgeInsets.only(left: 15),
        );
      },
    );
  }

  Future<int> _getCalories(List<BluetoothService> services) async {
    while (isDeviceRead) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isDeviceRead = true;
    try {
      int calories =
          await Future.delayed(const Duration(milliseconds: 100), () async {
        final service = services.firstWhere((service) =>
            service.uuid.toString() == '0000fee0-0000-1000-8000-00805f9b34fb');

        final characteristic = service.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00000007-0000-3512-2118-0009af100700');

        final data = await characteristic.read();
        return _byteIntToUint16(data, 9, Endian.little);
      });

      debugPrint('Calories: $calories');
      isDeviceRead = false;
      return calories;
    } catch (e) {
      debugPrint('Error $e');
      isDeviceRead = false;
      return 0;
    }
  }

  FutureBuilder _buildCalories(List<BluetoothService> services) {
    return FutureBuilder<int>(
      future: _getCalories(services),
      builder: (context, AsyncSnapshot<int> snapshot) {
        return ListTile(
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Calories'),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? Text('Loading...',
                      style: Theme.of(context).textTheme.bodyText1?.copyWith(
                          color: Theme.of(context).textTheme.caption?.color))
                  : (!snapshot.hasData)
                      ? const Text('Get Calories Error Code: 1')
                      : (snapshot.hasData)
                          ? Text(snapshot.data.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .caption
                                          ?.color))
                          : (snapshot.hasError)
                              ? Text('${snapshot.error}')
                              : const Text('Get Calories Error Code: 2')
            ],
          ),
          contentPadding: const EdgeInsets.only(left: 15),
        );
      },
    );
  }

  Future<int> _getHeartRate(List<BluetoothService> services) async {
    while (isDeviceRead) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isDeviceRead = true;

    try {
      int heartRate =
          await Future.delayed(const Duration(milliseconds: 100), () async {
        final service = services.firstWhere((service) =>
            service.uuid.toString() == '0000180d-0000-1000-8000-00805f9b34fb');

        final characteristic = service.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00002a39-0000-1000-8000-00805f9b34fb');

        final serviceRead = services.firstWhere((service) =>
            service.uuid.toString() == '0000180d-0000-1000-8000-00805f9b34fb');

        final characteristicRead = serviceRead.characteristics.firstWhere(
            (characteristic) =>
                characteristic.uuid.toString() ==
                '00002a37-0000-1000-8000-00805f9b34fb');

        await characteristicRead.setNotifyValue(true);
        await characteristic.write([21, 1, 0]);
        await characteristic.write([21, 2, 0]);
        await characteristic.write([21, 2, 1]);

        List<int> data = [];

        var subscription = characteristicRead.value.listen((value) {
          if (value.isNotEmpty && value != []) {
            debugPrint(value.toString());
            data = value;
          }
        });

        while (data.isEmpty) {
          await Future.delayed(const Duration(seconds: 1));
        }

        subscription.cancel();
        isDeviceRead = false;
        return _byteIntToUint16(data, 0, Endian.big);
      });

      debugPrint('HeartRate: $heartRate');

      return heartRate;
    } catch (e) {
      debugPrint('Error $e');
      isDeviceRead = false;
      return 0;
    }
  }

  FutureBuilder _buildHeartRate(List<BluetoothService> services) {
    return FutureBuilder<int>(
      future: _getHeartRate(services),
      builder: (context, AsyncSnapshot<int> snapshot) {
        return ListTile(
          title: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('HeartRate'),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? Text('Loading...',
                      style: Theme.of(context).textTheme.bodyText1?.copyWith(
                          color: Theme.of(context).textTheme.caption?.color))
                  : (!snapshot.hasData)
                      ? const Text('Get HeartRate Error Code: 1')
                      : (snapshot.hasData)
                          ? Text(snapshot.data.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyText1
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .caption
                                          ?.color))
                          : (snapshot.hasError)
                              ? Text('${snapshot.error}')
                              : const Text('Get HeartRate Error Code: 2')
            ],
          ),
          contentPadding: const EdgeInsets.only(left: 15),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: <Widget>[
          StreamBuilder<BluetoothDeviceState>(
            stream: widget.device.state,
            initialData: BluetoothDeviceState.connecting,
            builder: (c, snapshot) {
              VoidCallback onPressed;
              String text;
              switch (snapshot.data) {
                case BluetoothDeviceState.connected:
                  onPressed = () => widget.device.disconnect();
                  text = 'DISCONNECT';
                  break;
                case BluetoothDeviceState.disconnected:
                  onPressed = () => widget.device.connect();
                  text = 'CONNECT';
                  break;
                default:
                  onPressed = () => {};
                  text = snapshot.data.toString().substring(21).toUpperCase();
                  break;
              }
              return TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(88, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(2.0)),
                      )),
                  onPressed: onPressed,
                  child: Text(
                    text,
                    style: Theme.of(context)
                        .primaryTextTheme
                        .button
                        ?.copyWith(color: Colors.white),
                  ));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            StreamBuilder<BluetoothDeviceState>(
              stream: widget.device.state,
              initialData: BluetoothDeviceState.connecting,
              builder: (c, snapshot) => ListTile(
                leading: (snapshot.data == BluetoothDeviceState.connected)
                    ? const Icon(Icons.bluetooth_connected)
                    : const Icon(Icons.bluetooth_disabled),
                title: Text(
                    'Device is ${snapshot.data.toString().split('.')[1]}.'),
                subtitle: Text('${widget.device.id}'),
                trailing: StreamBuilder<bool>(
                  stream: widget.device.isDiscoveringServices,
                  initialData: false,
                  builder: (c, snapshot) => IndexedStack(
                    index: snapshot.data! ? 1 : 0,
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          widget.device.discoverServices();
                        },
                      ),
                      const IconButton(
                        icon: SizedBox(
                          width: 18.0,
                          height: 18.0,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.grey),
                          ),
                        ),
                        onPressed: null,
                      )
                    ],
                  ),
                ),
              ),
            ),
            ListTile(
              title: const Text('Auth Device Status'),
              subtitle: Text('$_authStatus'),
              trailing: IconButton(
                icon: _authStatus == true
                    ? const Icon(Icons.verified_user)
                    : const Icon(Icons.add),
                onPressed: () => _authDevice(widget.device),
              ),
            ),
            StreamBuilder<List<BluetoothService>>(
              stream: widget.device.services,
              initialData: const [],
              builder: (c, snapshot) {
                return _authStatus == true
                    ? Column(
                        children: [
                          _buildDateTime(snapshot.data!),
                          _buildBatteryLevel(snapshot.data!),
                          _buildStep(snapshot.data!),
                          _buildDistance(snapshot.data!),
                          _buildCalories(snapshot.data!),
                          _buildHeartRate(snapshot.data!),
                        ],
                      )
                    : const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}

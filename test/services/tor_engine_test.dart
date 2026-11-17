// اختبارات Tor الصافية (بلا تنزيل ولا تشغيل).
import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/telegram_net/tor_engine.dart';

void main() {
  test('النسخة من downloads.json', () {
    expect(TorEngine.versionFromDownloadsJson('{"version":"15.0.2","downloads":{}}'), '15.0.2');
    expect(TorEngine.versionFromDownloadsJson('{"version":"../x"}'), isNull);
    expect(TorEngine.versionFromDownloadsJson('{}'), isNull);
  });

  test('البصمة من ملف البصمات (الاسم كاملاً لا جزءاً منه)', () {
    final name = TorEngine.bundleName('15.0.2');
    final sums = '${'a' * 64}  tor-browser-windows-x86_64-portable-15.0.2.exe\n'
        '${'b' * 64}  $name\n'
        '${'c' * 64}  $name.asc\n';
    expect(TorEngine.hashFor(sums, name), 'b' * 64);
    expect(TorEngine.hashFor(sums, 'missing.tar.gz'), isNull);
  });

  test('مسارات الأرشيف الخطرة تُتجاهل', () {
    expect(TorEngine.safeRelative('tor/tor.exe'), isNotNull);
    expect(TorEngine.safeRelative('./tor/pluggable_transports/lyrebird.exe'), isNotNull);
    expect(TorEngine.safeRelative('../evil.exe'), isNull);
    expect(TorEngine.safeRelative('tor/../../evil.exe'), isNull);
    expect(TorEngine.safeRelative('/etc/passwd'), isNull);
    expect(TorEngine.safeRelative(r'C:\Windows\evil.exe'), isNull);
  });

  const pt = '{"recommendedDefault":"obfs4",'
      '"pluggableTransports":{"lyrebird":"ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec \${pt_path}lyrebird",'
      '"snowflake":"ClientTransportPlugin snowflake exec \${pt_path}snowflake-client"},'
      '"bridges":{"obfs4":["obfs4 1.2.3.4:443 X"],"snowflake":["snowflake 192.0.2.3:80 2B28 url=https://x front=y","snowflake 192.0.2.4:80 8838 url=https://z"]}}';

  test('جسور Snowflake وبرنامجها من pt_config.json', () {
    expect(TorEngine.bridgesFromPtConfig(pt, 'snowflake')!.length, 2);
    expect(TorEngine.bridgesFromPtConfig(pt, 'meek'), isNull);
    expect(TorEngine.snowflakeExecName(pt), 'snowflake-client.exe');
    const modern = '{"pluggableTransports":{"lyrebird":"ClientTransportPlugin meek_lite,obfs4,snowflake,webtunnel exec \${pt_path}lyrebird"}}';
    expect(TorEngine.snowflakeExecName(modern), 'lyrebird.exe');
  });

  test('ملف torrc: محلي فقط، يُغلق مع البرنامج، وجسور Snowflake', () {
    final t = TorEngine.buildTorrc(
      dataDir: r'C:\Users\a b\AppData\tor\data',
      socksPort: 50123,
      lyrebird: 'lyrebird.exe',
      bridges: ['snowflake 192.0.2.3:80 X'],
      ownerPid: 4242,
    );
    expect(t, contains('SocksPort 127.0.0.1:50123'));
    expect(t, contains('__OwningControllerProcess 4242'));
    expect(t, contains('ClientTransportPlugin snowflake exec lyrebird.exe'));
    expect(t, contains('Bridge snowflake 192.0.2.3:80 X'));
    expect(t, contains(r'DataDirectory "C:\\Users\\a b\\AppData\\tor\\data"'));
    expect(t, contains('UseBridges 1'));
  });
}

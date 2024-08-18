import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:io' as io;
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

// init
void init() {
  WidgetsFlutterBinding.ensureInitialized();
  Permission.storage.request();
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YouTube Downloader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String _status = '';
  final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();

 

Future<void> _downloadVideo(String url) async {
  setState(() {
    _isLoading = true;
    _status = 'Downloading...';
  });

  try {
    // Request video info from the server
    var response = await http.post(
      Uri.parse('http://your-server-url/getVideoInfo'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"url": url}),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);

      var title = data['title'];
      var sanitizedTitle = _sanitizeFileName(title);

      var directory = io.Directory('/storage/emulated/0/Download/');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Show quality dialog to the user
      var selectedStreamInfo = await _showQualityDialog(data['streams']);

      if (selectedStreamInfo != null) {
        // Download the selected video and audio from the server
        var videoFilePath = '${directory.path}/${sanitizedTitle}_video.mp4';
        var audioFilePath = '${directory.path}/${sanitizedTitle}_audio.mp4';
        var mergedFilePath = '${directory.path}/${sanitizedTitle}.mp4';

        await _downloadFile(data['streams'][selectedStreamInfo]['videoUrl'], videoFilePath);
        await _downloadFile(data['streams'][selectedStreamInfo]['audioUrl'], audioFilePath);

        // Merge video and audio using FFmpeg
        await _mergeVideoAndAudio(videoFilePath, audioFilePath, mergedFilePath);

        setState(() {
          _isLoading = false;
          _status = 'Download completed: $mergedFilePath';
        });

        // Notify media scanner
        await _scanFile(mergedFilePath);

        // Clean up
        File(videoFilePath).deleteSync();
        File(audioFilePath).deleteSync();
      } else {
        setState(() {
          _isLoading = false;
          _status = 'Download cancelled';
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _status = 'Server Error: ${response.statusCode}';
      });
    }
  } catch (e) {
    setState(() {
      _isLoading = false;
      _status = 'Error: $e';
    });
  }
}

Future<void> _downloadFile(String url, String filePath) async {
  var response = await http.get(Uri.parse(url));
  var file = File(filePath);
  await file.writeAsBytes(response.bodyBytes);
}


  Future<int?> _showQualityDialog(List<dynamic> streams) async {
  return showDialog<int>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Select Quality'),
        content: SingleChildScrollView(
          child: ListBody(
            children: List.generate(streams.length, (index) {
              var stream = streams[index];
              return ListTile(
                title: Text(
                    '${stream['qualityLabel']} (${stream['size']} MB)'),
                onTap: () {
                  Navigator.of(context).pop(index);
                },
              );
            }),
          ),
        ),
      );
    },
  );
}



  Future<void> _mergeVideoAndAudio(
      String videoPath, String audioPath, String outputPath) async {
    // Use FFmpeg to merge video and audio
    String command =
        '-i "$videoPath" -i "$audioPath" -c:v copy -c:a aac -strict experimental "$outputPath"';
    await _flutterFFmpeg.execute(command);
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
  }

  Future<void> _scanFile(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      try {
        const methodChannel = MethodChannel('com.example.flutter_youtube_downloader');
        await methodChannel.invokeMethod('scanFile', {'path': filePath});
      } catch (e) {
        print('Error scanning file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('YouTube Downloader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Enter YouTube video URL',
              ),
            ),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () async {
                      await _downloadVideo(_controller.text);
                    },
                    child: Text('Download'),
                  ),
            SizedBox(height: 20),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
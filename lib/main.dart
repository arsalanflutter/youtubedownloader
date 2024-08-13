import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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
      var yt = YoutubeExplode();
      var videoId = VideoId(url);
      var video = await yt.videos.get(videoId);
      var title = video.title;
      var sanitizedTitle = _sanitizeFileName(title);

      var manifest = await yt.videos.streamsClient.getManifest(videoId);

      var directory = io.Directory('/storage/emulated/0/Download/');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Select quality
      var selectedStreamInfo = await _showQualityDialog(manifest);

      if (selectedStreamInfo != null) {
        // Download video and audio separately
        var videoStream = yt.videos.streamsClient.get(selectedStreamInfo);
        var audioStreamInfo = manifest.audio.withHighestBitrate();
        var audioStream = yt.videos.streamsClient.get(audioStreamInfo);

        var videoFilePath = '${directory.path}/${sanitizedTitle}_video.mp4';
        var audioFilePath = '${directory.path}/${sanitizedTitle}_audio.mp4';
        var mergedFilePath = '${directory.path}/${sanitizedTitle}.mp4';

        // Save video file
        var videoFile = File(videoFilePath);
        var videoFileStream = videoFile.openWrite();
        await videoStream.pipe(videoFileStream);
        await videoFileStream.flush();
        await videoFileStream.close();

        // Save audio file
        var audioFile = File(audioFilePath);
        var audioFileStream = audioFile.openWrite();
        await audioStream.pipe(audioFileStream);
        await audioFileStream.flush();
        await audioFileStream.close();

        // Merge video and audio using FFmpeg
        await _mergeVideoAndAudio(videoFilePath, audioFilePath, mergedFilePath);

        setState(() {
          _isLoading = false;
          _status = 'Download completed: $mergedFilePath';
        });

        // Notify media scanner
        await _scanFile(mergedFilePath);

        // Clean up
        videoFile.deleteSync();
        audioFile.deleteSync();
      } else {
        setState(() {
          _isLoading = false;
          _status = 'Download cancelled';
        });
      }

      yt.close();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<StreamInfo?> _showQualityDialog(StreamManifest manifest) async {
    return showDialog<StreamInfo>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Quality'),
          content: SingleChildScrollView(
            child: ListBody(
              children: manifest.video.map((streamInfo) {
                return ListTile(
                  title: Text(
                      '${streamInfo.videoQualityLabel} (${streamInfo.size.totalMegaBytes.toStringAsFixed(2)} MB)'),
                  onTap: () {
                    Navigator.of(context).pop(streamInfo);
                  },
                );
              }).toList(),
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

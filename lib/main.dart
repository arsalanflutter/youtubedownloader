import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

  Future<void> _downloadVideo(String url) async {
    setState(() {
      _isLoading = true;
      _status = 'Downloading...';
    });

    var yt = YoutubeExplode();
    var videoId = VideoId(url);
    var manifest = await yt.videos.streamsClient.getManifest(videoId);
    var streamInfo = manifest.muxed.withHighestBitrate();
    var stream = yt.videos.streamsClient.get(streamInfo);

    var directory = await getExternalStorageDirectory();
    var filePath = '${directory!.path}/${videoId.value}.mp4';
    var file = File(filePath);

    var fileStream = file.openWrite();
    await stream.pipe(fileStream);
    await fileStream.flush();
    await fileStream.close();

    yt.close();

    setState(() {
      _isLoading = false;
      _status = 'Download completed: $filePath';
    });
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
                      if (await Permission.storage.request().isGranted) {
                        _downloadVideo(_controller.text);
                      }
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

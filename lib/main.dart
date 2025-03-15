import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:loader_overlay/loader_overlay.dart';

class Message {
  late String message;
  late bool isSentByMe;
  late String time;
  late int emoNum;

  Message({required str, required user, required time, required emoNum}) {
    this.message = str;
    this.isSentByMe = user;
    this.time = time;
    this.emoNum = emoNum;
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Siren',
      theme: ThemeData(
        primaryColor: Colors.white, // 앱의 주 색상
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const MyHomePage(title: 'Siren'),
    );
  }
}

// Feed your own stream of bytes into the player
class MyCustomSource extends StreamAudioSource {
  final List<int> bytes;
  MyCustomSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Duration _totalDuration = Duration.zero;
  double _currentPositionPercentage = 0.0;
  String imgStr = '';
  String baseUrl = 'http://211.212.160.140:5000/files';
  String uploadUrl = 'http://211.212.160.140:5001/upload';
  String imgUrl = '';
  String mTitle = "";
  String mArtist = "";
  String mUrl = "";
  String pUrl = "http://211.212.160.140:5000/playinginfo";
  String eUrl = "http://211.212.160.140:5000/emoinfo";
  List<Message> _messages = [];
  bool isPlaying = false;
  TextEditingController? _messageTextEditingController;
  ScrollController? _messageScrollController;
  bool isSideSheetOpen = false;
  bool isBottomSheetOpen = false;
  late IO.Socket socket;
  final AudioPlayer player = AudioPlayer();
  final AudioPlayer uploadPlayer = AudioPlayer();
  bool isEmoClicked = false;
  int isEmoSelected = -1;
  List<dynamic> emojis = [];
  Color domColor = Colors.white;
  Message? userLastMessage;
  Uint8List? _selectImageAsBytes;
  Uint8List? _uploadAudioBytes;
  bool isAudioSelected = false;
  bool isUploadPlayerPlaying = false;
  TextEditingController? _uploadTitleController;
  TextEditingController? _uploadartistController;

  Future<void> getEmoInfo() async{
    final response = await http.get(
      Uri.parse(eUrl),
    );
    if (response.statusCode == 200) {
      setState(() {
        emojis = jsonDecode(response.body);
      });
    } else {
      print('server error');
    }
  }

  Future<Duration> getMusicInfo() async {
    var mDuration = 0;
    try {
      final response = await http.get(
        Uri.parse(pUrl),
      );

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        mArtist = json['artist'];
        mTitle = json['title'];
        imgUrl = baseUrl + '/albumarts/' + json['albumart'];
        mUrl = baseUrl + '/musics/' + json['music'];
        mDuration = int.parse(json['duration']);
        await getDominantColor(imgUrl);
        setState(() {});
      } else {

      }
    } catch (e) {
      print(e);
      print('error');
    }
    return Duration(seconds: mDuration);
  }

  Widget EmoWidget(int index){
    int isMobile = isBottomSheetOpen ? 1 : 3;
    return Container(
      width: MediaQuery.of(context).size.width/isMobile*0.4,
      height: MediaQuery.of(context).size.width/isMobile*0.4,
      margin: EdgeInsets.all(5),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(
              baseUrl+'/emoticons/'+emojis[index],
          ),
          fit: BoxFit.cover
        ),
      ),
    );
  }

  Widget EmoKeyboardAnimatedWidget() {
    return AnimatedOpacity(
      opacity: isEmoClicked ? 1 : 0,
      duration: Duration(milliseconds: 100),
      child: Visibility(
        visible: isEmoClicked,
        child: Container(
          color: domColor.withOpacity(0.4),
          height: 200,
          child: GridView.builder(
            padding: EdgeInsets.all(8.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8.0,
              mainAxisSpacing: 8.0,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if(isEmoSelected == -1){
                      isEmoSelected = index;
                    }else{
                      if(isEmoSelected == index){
                        isEmoSelected = -1;
                      }else{
                        isEmoSelected = index;
                      }
                    }
                  });
                },
                onDoubleTap: (){
                  submitMessage("", context, index);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isEmoSelected == index ? Colors.black.withOpacity(0.3) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: NetworkImage(
                            baseUrl+'/emoticons/'+emojis[index]
                          ),
                          fit: BoxFit.cover
                        )
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
  Widget ChatServiceWidget(){
    return Expanded(
      child: ListView.builder(
        controller: _messageScrollController,
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Column(
              crossAxisAlignment: _messages[index].isSentByMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                _messages[index].emoNum != -1 ? EmoWidget(_messages[index].emoNum) : SizedBox(),
                _messages[index].message != '' ? AnimatedContainer(
                  color: _messages[index].isSentByMe
                      ? (domColor.withOpacity(0.5) ??
                      Colors.grey)
                      : (domColor.withOpacity(0.4) ??
                      Colors.black12),
                  duration: Duration(milliseconds: 100),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        0.7,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, 5, 10, 5),
                    child: Text(
                      _messages[index].message,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: 'SCDream',
                      ),
                    ),
                  ),
                ):SizedBox(),
                SizedBox(height: 5),
                Text(
                  _messages[index].time.substring(11, 16),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'SCDream',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget bottomSheetAnimatedWidget() {
    if (isSideSheetOpen) {
      isSideSheetOpen = false;
      isBottomSheetOpen = true;
    }
    return AnimatedPositioned(
      curve: Curves.ease,
      duration: Duration(milliseconds: 200),
      // 애니메이션의 지속 시간 설정
      right: 0,
      bottom: isBottomSheetOpen
          ? 0
          : -MediaQuery.of(context).size.height +
              MediaQuery.of(context).padding.top,
      height: MediaQuery.of(context).size.height -
          MediaQuery.of(context).padding.top,
      width: MediaQuery.of(context).size.width,
      child: Stack(
        children: [
          Container(
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  height: 125,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, 15, 10, 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        LayoutBuilder(
                          builder: (BuildContext context,
                              BoxConstraints constraints) {
                            double parentHeight = constraints.maxHeight;
                            return Container(
                              height: parentHeight,
                              width: parentHeight,
                              decoration: BoxDecoration(
                                image: DecorationImage(
                                    image: NetworkImage(imgUrl),
                                    fit: BoxFit.cover),
                              ),
                            );
                          },
                        ),
                        SizedBox(
                          width: 10,
                        ),
                        Expanded(
                            child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mTitle,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SCDream'),
                            ),
                            Text(
                              mArtist,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.normal,
                                  fontFamily: 'SCDream'),
                            ),
                            Container(
                              margin: EdgeInsets.fromLTRB(0, 10, 0, 10),
                              // 여기서 마진을 제거합니다.
                              child: LinearProgressIndicator(
                                backgroundColor: domColor.withOpacity(0.4),
                                color: domColor.withOpacity(1),
                                value: _currentPositionPercentage,
                              ),
                            ),
                          ],
                        )),
                        Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 10, 0),
                          child: InkWell(
                            customBorder: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(60),
                            ),
                            child: DottedBorder(
                              strokeWidth: 0.6,
                              borderType: BorderType.RRect,
                              radius: Radius.circular(60),
                              child: ClipRRect(
                                  child: Padding(
                                padding: EdgeInsets.all(8),
                                child: isPlaying
                                    ? Icon(Icons.stop, size: 20)
                                    : Icon(Icons.play_arrow_sharp, size: 20),
                              )),
                            ),
                            onTap: () {
                              if (isPlaying) {
                                setState(() {
                                  isPlaying = false;
                                  player.pause();
                                });
                                setState(() {});
                              } else {
                                setState(() {
                                  isPlaying = true;
                                  playAudio();
                                });
                                setState(() {});
                              }
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                ChatServiceWidget(),
                EmoKeyboardAnimatedWidget(),
                Container(
                  height: 50,
                  child: Container(
                    color: domColor.withOpacity(0.4),
                    padding: EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.emoji_emotions_outlined),
                          onPressed: () {
                            setState(() {
                              if (isEmoClicked) {
                                isEmoClicked = false;
                              } else {
                                isEmoClicked = true;
                              }
                            });
                          },
                        ),
                        Expanded(
                          child: TextField(
                            textInputAction: TextInputAction.go,
                            onSubmitted: (value) async {
                              setState(() {
                                submitMessage(
                                    _messageTextEditingController!.text,
                                    context,isEmoSelected);
                              });
                            },
                            controller: _messageTextEditingController,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: 'Type your message...',
                              isDense: true,
                              contentPadding: EdgeInsets.all(7),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(4)),
                                borderSide: BorderSide(
                                  width: 1,
                                  color: domColor.withOpacity(0.8),
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(4)),
                                borderSide: BorderSide(
                                  width: 1,
                                  color: domColor.withOpacity(0.4),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(4)),
                                borderSide: BorderSide(
                                  width: 1,
                                  color: domColor.withOpacity(0.6),
                                ),
                              ),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(4)),
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: domColor.withOpacity(0.2),
                                  )),
                              errorBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(4)),
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: domColor.withOpacity(0.4),
                                  )),
                              focusedErrorBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(4)),
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: domColor.withOpacity(0.4),
                                  )),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.0),
                        IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.send),
                          // 보내기 모양의 아이콘
                          onPressed: () {
                            setState(() {
                              submitMessage(
                                  _messageTextEditingController!.text,
                                  context,isEmoSelected);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: MediaQuery.of(context).size.width / 2 - 30,
            top: 0,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isBottomSheetOpen = false;
                });
              },
              child: Container(
                width: 60,
                height: 20,
                decoration: BoxDecoration(
                  color: domColor.withOpacity(0.3),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(35),
                    bottomRight: Radius.circular(35),
                  ),
                ),
                child: Icon(
                  Icons.arrow_drop_down_sharp,
                  size: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget sideSheetAnimatedWidget() {
    if (isBottomSheetOpen) {
      isBottomSheetOpen = false;
      isSideSheetOpen = true;
    }
    return AnimatedPositioned(
        curve: Curves.ease,
        duration: Duration(milliseconds: 200),
        right: isSideSheetOpen ? 0 : -MediaQuery.of(context).size.width * 0.3,
        top: 0,
        bottom: 0,
        width: MediaQuery.of(context).size.width * 0.3,
        child: Stack(
          children: [
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  ChatServiceWidget(),
                  EmoKeyboardAnimatedWidget(),
                  Container(
                    height: 50,
                    child: Container(
                      color: domColor.withOpacity(0.4),
                      padding: EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.emoji_emotions_outlined),
                            onPressed: () {
                              setState(() {
                                if (isEmoClicked)
                                  isEmoClicked = false;
                                else
                                  isEmoClicked = true;
                              });
                            },
                          ),
                          Expanded(
                            child: TextField(
                              textInputAction: TextInputAction.go,
                              onSubmitted: (value) async {
                                setState(() {
                                  submitMessage(
                                      _messageTextEditingController!.text,
                                      context,isEmoSelected);
                                });
                              },
                              controller: _messageTextEditingController,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                hintText: 'Type your message...',
                                isDense: true,
                                contentPadding: EdgeInsets.all(7),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(4)),
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: domColor.withOpacity(0.8),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(4)),
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: domColor.withOpacity(0.4),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(4)),
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: domColor.withOpacity(0.6),
                                  ),
                                ),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(4)),
                                    borderSide: BorderSide(
                                      width: 1,
                                      color: domColor.withOpacity(0.2),
                                    )),
                                errorBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(4)),
                                    borderSide: BorderSide(
                                      width: 1,
                                      color: domColor.withOpacity(0.4),
                                    )),
                                focusedErrorBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(4)),
                                    borderSide: BorderSide(
                                      width: 1,
                                      color: domColor.withOpacity(0.4),
                                    )),
                              ),
                            ),
                          ),
                          SizedBox(width: 8.0),
                          IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.send_sharp),
                            // 보내기 모양의 아이콘
                            onPressed: () {
                              setState(() {
                                submitMessage(
                                    _messageTextEditingController!.text,
                                    context,isEmoSelected);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: MediaQuery.of(context).size.height / 2 -
                  25, // 시트의 높이의 중간에 위치하도록 설정
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    isSideSheetOpen = false;
                  });
                },
                child: Container(
                  width: 20,
                  height: 60,
                  decoration: BoxDecoration(
                    color: domColor.withOpacity(0.3),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(35),
                      bottomRight: Radius.circular(35),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_right,
                    size: 15,
                  ),
                ),
              ),
            ),
          ],
        ));
  }

  void playAudio() async {
    Duration dur = await getMusicInfo();
    await player.setAudioSource(AudioSource.uri(Uri.parse(mUrl)));
    await player.seek(dur);
    await player.play();
  }


  void connectToServer() {
    socket = IO.io('http://211.212.160.140:5000', <String, dynamic>{
      'transports': ['websocket'],
    });

    socket.on('connect', (_) { //연결됐을때 할 일
    });

    socket.on('message', (jsonData) { //메시지 받았을 때
      Map<String, dynamic> data = jsonData;
      setState(() {
      });
      if(userLastMessage != null){
        if(data['content'] != userLastMessage?.message || data['timestamp'].toString() != userLastMessage?.time.toString()){
          _messages.add(Message(str: data['content'], user: false, time: data['timestamp'], emoNum: data['emonum']));
          scrollSheetToBottom();
        }
      }else{
        _messages.add(Message(str: data['content'], user: false, time: data['timestamp'], emoNum: data['emonum']));
        scrollSheetToBottom();
      }

      scrollSheetToBottom();
    });

    socket.connect();
  }

  static Future<ui.Image> bytesToImage(Uint8List imgBytes) async{
    ui.Codec codec = await ui.instantiateImageCodec(imgBytes);
    ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> getDominantColor(String imageUrl) async {
    final http.Response responseData = await http.get(Uri.parse(imageUrl));
    Uint8List lst = responseData.bodyBytes;
    Image.memory(lst);
    var img = await bytesToImage(lst);
    var paletteGenerator = await PaletteGenerator.fromImage(
        img
    );
    domColor = paletteGenerator.dominantColor!.color;
  }

  void scrollSheetToBottom() {
    setState(() {

    });
    _messageScrollController!.animateTo(
      _messageScrollController!.position.maxScrollExtent,
      duration: Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void submitMessage(String str, BuildContext context, int emoNum) {
    if(str.isEmpty && emoNum == -1)
      return;
    String time = DateTime.now().toIso8601String();

    setState(() {
      _messages.add(Message(
          str: str, user: true, time: time, emoNum: emoNum));
      userLastMessage = Message(str: str, user: true, time: time, emoNum: emoNum);
      _messageTextEditingController?.text = '';
      FocusScope.of(context).unfocus();
      isEmoSelected = -1;
    });
    setState(() {
      scrollSheetToBottom();
    });
    Map<String, dynamic> data = {
      'content': str,
      'sender': 'Flutter Client',
      'timestamp': time,
      'emonum' : emoNum
    };
    socket.emit('message', data);
  }

  void playNextMusic() async {
    await getMusicInfo();
    playAudio();
  }

  @override
  void dispose(){
    super.dispose();
    player.dispose();
    uploadPlayer.dispose();
    _messageScrollController?.dispose();
    _messageTextEditingController?.dispose();
    _messageScrollController?.dispose();
    _uploadartistController?.dispose();
    _uploadTitleController?.dispose();
    socket.disconnect(); //연결 해제
  }

  @override
  void initState() {
    super.initState();
    getEmoInfo();
    getMusicInfo();
    _messageTextEditingController = TextEditingController();
    _messageScrollController = ScrollController();
    _uploadartistController = TextEditingController();
    _uploadTitleController = TextEditingController();
    player.durationStream.listen((duration) {
      setState(() {
        _totalDuration = duration ?? Duration.zero;
      });
    });
    player.positionStream.listen((Duration position) {
      setState(() {
        double tmpVal =
            (position.inMilliseconds / _totalDuration.inMilliseconds);
        if (tmpVal.isNaN) {
          _currentPositionPercentage = 0.0;
        } else {
          _currentPositionPercentage = tmpVal;
        }
      });
    });
    player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        playNextMusic();
      }
    });
    connectToServer();
  }

  Widget RemoteUploadMusicWidget(StateSetter setState){
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(onPressed: (){
          _openAudioPicker(setState);
        }, icon: Icon(Icons.folder)),
        isAudioSelected?
        IconButton(onPressed: (){
          if(isUploadPlayerPlaying){
            uploadPlayer.stop();
            uploadPlayer.seek(Duration.zero);
            isUploadPlayerPlaying = false;
          }else{
            if(isPlaying)
              player.stop();
            uploadPlayer.play();
            isUploadPlayerPlaying = true;
          }
          setState((){
          });
        }, icon: isUploadPlayerPlaying ? Icon(Icons.stop_circle) : Icon(Icons.play_circle,),):
        Text('No music selected')
      ],
    );
  }

  void showUploadDialog(){
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: ((context) {
        return StatefulBuilder(builder: (context, setState){
          return LoaderOverlay(child: AlertDialog(
            title: Text(
              "Upload (BETA)",
              style: TextStyle(
                  fontFamily: "SCDream",
                  fontWeight: FontWeight.bold
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        image: _selectImageAsBytes != null?
                        DecorationImage(
                          image: Image.memory(_selectImageAsBytes!, fit: BoxFit.cover,).image,
                        ):
                        null,
                      ),
                      child: DottedBorder(
                          strokeWidth: 1.5,
                          color: Colors.grey,
                          borderType: BorderType.RRect,
                          child: Center(
                            child: IconButton(
                              color: domColor.withOpacity(0.6),
                              icon: Icon(Icons.add_circle_outline),
                              onPressed: (){
                                _openImagePicker(setState);
                              },
                            ),
                          )
                      ),
                    ),
                  ),

                  SizedBox(height: 20),
                  TextField(
                    controller: _uploadTitleController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      isDense: true,
                      contentPadding: EdgeInsets.all(7),
                    ),
                    style: TextStyle(
                        fontFamily: "SCDream"
                    ),
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: _uploadartistController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Artist',
                      isDense: true,
                      contentPadding: EdgeInsets.all(7),
                    ),
                    style: TextStyle(
                        fontFamily: "SCDream"
                    ),
                  ),
                  SizedBox(height: 20),
                  Text("Select music", style: TextStyle(fontFamily: "SCDream", fontSize: 14, fontWeight: FontWeight.bold),),
                  SizedBox(height: 10),
                  RemoteUploadMusicWidget(setState)

                ],
              ),
            ),
            actions: <Widget>[
              IconButton(
                onPressed: () async {
                  context.loaderOverlay.show();
                  await _uploadMusic();
                  context.loaderOverlay.hide();
                  Navigator.of(context).pop();
                },
                icon:Icon(Icons.save_outlined),
              ),
              IconButton(
                onPressed: () {
                  if(isAudioSelected){
                    isUploadPlayerPlaying = false;
                    uploadPlayer.seek(Duration.zero);
                  }
                  Navigator.of(context).pop(); // Close dialog
                  uploadPlayer.stop();
                },
                icon:Icon(Icons.cancel_outlined),
              ),
            ],
          ));
        });
      }),
    );
  }

  Future<void> _uploadMusic() async{
    String requestBodyJson="";
    int dur = 0;
    try {
      dur = uploadPlayer.duration!.inSeconds;
      requestBodyJson = json.encode({
        'music': _uploadAudioBytes,
        'albumart': _selectImageAsBytes,
        'title': _uploadTitleController!.text,
        'artist': _uploadartistController!.text,
        'duration': dur.toString()
      });
    }catch(e){
      print("fill all");
    }
    final response = await http.post(
      Uri.parse(uploadUrl),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: requestBodyJson,
    );
    if (response.statusCode == 200) {
      _uploadAudioBytes = null;
      _selectImageAsBytes = null;
      _uploadTitleController!.text = "";
      _uploadartistController!.text = "";
      uploadPlayer.stop();
      isAudioSelected = false;
      isUploadPlayerPlaying = false;

      final snackBar = SnackBar(
        content: Text('Upload complete!'),
        duration: Duration(seconds: 2),
        backgroundColor: domColor,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      print('server error');
      print(response.statusCode);
    }
  }

  void _openImagePicker(StateSetter setState) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
      ],
    );
    if (result != null) {
      _selectImageAsBytes = result.files.first.bytes;
      setState(() {
      });
    } else {
      // User canceled the picker
    }
  }

  void _openAudioPicker(StateSetter setState) async {
    context.loaderOverlay.show();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
      ],
    );
    if (result != null) {
      _uploadAudioBytes = result.files.first.bytes;
      await uploadPlayer.setAudioSource(MyCustomSource(_uploadAudioBytes as List<int>));
      setState(() {
        isAudioSelected = true;
      });
    } else {

    }
    context.loaderOverlay.hide();
  }

  Widget MusicRemoteBar(){
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Icon(
              Icons.favorite_outline_sharp,
              size: 30,
            ),
          ),
          onTap: () {
            setState(() {
              if (isSideSheetOpen)
                isSideSheetOpen = false;
              else
                isSideSheetOpen = true;
            });
            print("clicked");
          },
        ),
        InkWell( //2번째 기능
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Icon(
              Icons.add_box_outlined,
              size: 30,
            ),
          ),
          onTap: () {
            setState(() {
              showUploadDialog();
            });
          },
        ),
        InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          child: DottedBorder(
            strokeWidth: 0.7,
            borderType: BorderType.RRect,
            radius: Radius.circular(60),
            child: ClipRRect(
                child: Padding(
                  padding: EdgeInsets.all(13),
                  child: isPlaying
                      ? Icon(Icons.stop, size: 30)
                      : Icon(Icons.play_arrow_sharp, size: 30),
                )),
          ),
          onTap: () {
            if (isPlaying) {
              setState(() {
                isPlaying = false;
                player.pause();
              });
            } else {
              setState(() {
                isPlaying = true;
                playAudio();
              });
            }
          },
        ),
        InkWell( //4번째 기능
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Icon(
              Icons.table_chart_outlined,
              size: 30,
            ),
          ),
          onTap: () {
            setState(() {

            });
          },
        ),
        InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(60),
            ),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.message_outlined,
                size: 30,
              ),
            ),
            onTap: () async {
              if (MediaQuery.of(context).size.width < 768) {
                setState(() {
                  if (isBottomSheetOpen)
                    isBottomSheetOpen = false;
                  else
                    isBottomSheetOpen = true;
                });
              } else {
                setState(() {
                  if (isSideSheetOpen)
                    isSideSheetOpen = false;
                  else
                    isSideSheetOpen = true;
                });
              }
            }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            AnimatedContainer(
              color: domColor.withOpacity(0.4),
              duration: Duration(seconds: 1),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        LayoutBuilder(
                          builder: (BuildContext context,
                              BoxConstraints constraints) {
                            double parentWidth = constraints.maxWidth;
                            return Container(
                              height: parentWidth,
                              width: parentWidth,
                              decoration: BoxDecoration(
                                image: DecorationImage(
                                    image: NetworkImage(imgUrl),
                                    fit: BoxFit.cover),
                              ),
                            );
                          },
                        ),
                        SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            Text(
                              mTitle,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SCDream'),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              mArtist,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.normal,
                                  fontFamily: 'SCDream'),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 10,
                        ),
                        Container(
                          margin: EdgeInsets.zero,
                          child: LinearProgressIndicator(
                            backgroundColor: domColor.withOpacity(0.4),
                            color: domColor,
                            value: _currentPositionPercentage,
                          ),
                        ),
                        SizedBox(
                          height: 25,
                        ),
                        MusicRemoteBar(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (MediaQuery.of(context).size.width > 768)
              sideSheetAnimatedWidget()
            else
              bottomSheetAnimatedWidget()
          ],
        );
      },
    ));
  }
}

import 'dart:collection';
import 'dart:io';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Gemini gemini = Gemini.instance;
  List<ChatMessage> messages = [];
  ChatUser currentUser = ChatUser(id: "0", firstName: "You");
  ChatUser geminiUser = ChatUser(id: "1", firstName: "Gemini");
  bool _isSummaryAvailable = false;

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    ChatMessage welcomeMessage = ChatMessage(
      user: geminiUser,
      createdAt: DateTime.now(),
      text:
          "Hello! I'm Gemini, your assistant for summarizing PDF files. To upload a PDF for summary, just tap the purple button in the bottom right corner. For downloading the result as PDF press the purple download button",
    );

    setState(() {
      messages = [welcomeMessage, ...messages];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "PDFSum",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.deepPurple,
      ),
      body: _buildUI(),
    );
  }

  Widget _buildUI() {
    return DashChat(
      inputOptions: InputOptions(
        trailing: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.deepPurple,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _sendPDFMessage,
                  icon: const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _isSummaryAvailable ? Colors.deepPurple : Colors.grey,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _isSummaryAvailable
                      ? _downloadResponseAsPDF
                      : null, // Disable if no summary
                  icon: const Icon(
                    Icons.download,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      currentUser: currentUser,
      onSend: _sendMessage,
      messages: messages,
    );
  }

  void _sendMessage(ChatMessage chatMessage) {
    setState(() {
      messages = [chatMessage, ...messages];
    });
    try {
      String userQuestion = chatMessage.text;
      gemini.streamGenerateContent(userQuestion).listen((event) {
        ChatMessage? lastMessage = messages.firstOrNull;
        // Check if the last message is from Gemini, if not, add the last message from Gemini to the list
        if (lastMessage != null && lastMessage.user == geminiUser) {
          lastMessage = messages.removeAt(0);
          String response = event.content?.parts?.fold(
                  "", (previous, current) => "$previous${current.text}") ??
              "";
          lastMessage.text += response;
          setState(() {
            messages = [lastMessage!, ...messages];
          });
        } else {
          String response = event.content?.parts?.fold(
                  "", (previous, current) => "$previous${current.text}") ??
              "";
          ChatMessage message = ChatMessage(
            user: geminiUser,
            createdAt: DateTime.now(),
            text: response,
          );
          setState(() {
            messages = [message, ...messages];
          });
        }
      });
    } catch (e) {
      print(e);
    }
  }

  void _sendPDFMessage() async {
    _showLoadingDialog();

    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      File file = File(result.files.single.path!);

      try {
        String pdfText = await _extractTextFromPDF(file);

        if (pdfText.isNotEmpty) {
          String summarizedText = await _summarizePDFText(pdfText);
          Navigator.of(context).pop();
          ChatMessage message = ChatMessage(
            user: geminiUser,
            createdAt: DateTime.now(),
            text: summarizedText,
          );

          setState(() {
            messages = [message, ...messages];
            _isSummaryAvailable = true; // Enable the download button
          });
        } else {
          // Remove the loading dialog
          Navigator.of(context).pop();
          print("Failed to extract text from the PDF.");
        }
      } catch (e) {
        print("Error during PDF analysis: $e");
        Navigator.of(context).pop();
      }
    }
  }

  void _downloadResponseAsPDF() async {
    if (messages.isNotEmpty) {
      ChatMessage? latestGeminiResponse = messages.firstWhere(
        (message) => message.user.id == geminiUser.id,
        orElse: () => ChatMessage(
          user: geminiUser,
          createdAt: DateTime.now(),
          text: "No response available to download.",
        ),
      );

      // Create a PDF document
      final PdfDocument document = PdfDocument();
      final PdfPage page = document.pages.add();

      // Add text to the PDF page
      page.graphics.drawString(
        latestGeminiResponse.text,
        PdfStandardFont(PdfFontFamily.helvetica, 18),
      );

      // Get the directory to save the file
      final directory = await getApplicationDocumentsDirectory();
      String formattedDate = DateTime.now().toString().replaceAll(':', '-');
      String path = "${directory.path}/${formattedDate}_GeminiResponse.pdf";
      // Save File to path
      File file = File(path);
      await file.writeAsBytes(await document.save());

      // Dispose the document
      document.dispose();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF saved at: $path")),
      );
      print(path);
    }
  }

  Future<String> _extractTextFromPDF(File file) async {
    try {
      // Load the PDF document
      final PdfDocument document =
          PdfDocument(inputBytes: file.readAsBytesSync());
      String extractedText = "";

      // Iterate through all pages to extract text
      for (int i = 0; i < document.pages.count; i++) {
        extractedText += PdfTextExtractor(document)
                .extractText(startPageIndex: i, endPageIndex: i) ??
            "";
      }

      // Dispose the document
      document.dispose();

      return extractedText;
    } catch (e) {
      print("Error extracting text from PDF: $e");
      return "";
    }
  }

  Future<String> _summarizePDFText(String pdfText) async {
    try {
      String summary = "";
      await for (var event
          in gemini.streamGenerateContent("Summarize this PDF:\n$pdfText")) {
        summary += event.content?.parts
                ?.fold("", (previous, current) => "$previous${current.text}") ??
            "";
      }
      return summary;
    } catch (e) {
      print("Error summarizing PDF text: $e");
      return "Failed to summarize the PDF.";
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text("Analyzing PDF, please wait..."),
              ],
            ),
          ),
        );
      },
    );
  }
}

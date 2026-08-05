import 'dart:convert';

class Notebook {
  String id;
  String name;
  int gradientIndex;
  String createdAt;
  List<Source> sources;
  List<OutlineNode> outline;
  List<Question> questions;
  List<ChatMessage> chatMessages;
  List<Mistake> mistakes;

  Notebook({
    required this.id,
    required this.name,
    required this.gradientIndex,
    required this.createdAt,
    List<Source>? sources,
    List<OutlineNode>? outline,
    List<Question>? questions,
    List<ChatMessage>? chatMessages,
    List<Mistake>? mistakes,
  })  : sources = sources ?? [],
        outline = outline ?? [],
        questions = questions ?? [],
        chatMessages = chatMessages ?? [],
        mistakes = mistakes ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gradientIndex': gradientIndex,
        'createdAt': createdAt,
        'sources': sources.map((e) => e.toJson()).toList(),
        'outline': outline.map((e) => e.toJson()).toList(),
        'questions': questions.map((e) => e.toJson()).toList(),
        'chatMessages': chatMessages.map((e) => e.toJson()).toList(),
        'mistakes': mistakes.map((e) => e.toJson()).toList(),
      };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
        id: json['id'] as String,
        name: json['name'] as String,
        gradientIndex: (json['gradientIndex'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        sources: (json['sources'] as List? ?? [])
            .map((e) => Source.fromJson(e as Map<String, dynamic>))
            .toList(),
        outline: (json['outline'] as List? ?? [])
            .map((e) => OutlineNode.fromJson(e as Map<String, dynamic>))
            .toList(),
        questions: (json['questions'] as List? ?? [])
            .map((e) => Question.fromJson(e as Map<String, dynamic>))
            .toList(),
        chatMessages: (json['chatMessages'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        mistakes: (json['mistakes'] as List? ?? [])
            .map((e) => Mistake.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get totalChunks =>
      sources.fold(0, (sum, s) => sum + (s.chunks?.length ?? 0));
}

class Source {
  String id;
  String name;
  String type; // text | file | obsidian | chat
  String rawText;
  String? filePath;
  String createdAt;
  List<Chunk>? chunks;

  Source({
    required this.id,
    required this.name,
    required this.type,
    required this.rawText,
    this.filePath,
    required this.createdAt,
    this.chunks,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'rawText': rawText,
        'filePath': filePath,
        'createdAt': createdAt,
        'chunks': chunks?.map((e) => e.toJson()).toList(),
      };

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String? ?? 'text',
        rawText: json['rawText'] as String? ?? '',
        filePath: json['filePath'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        chunks: (json['chunks'] as List? ?? [])
            .map((e) => Chunk.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Chunk {
  int index;
  String text;
  String? sourceName;

  Chunk({required this.index, required this.text, this.sourceName});

  Map<String, dynamic> toJson() =>
      {'index': index, 'text': text, 'sourceName': sourceName};

  factory Chunk.fromJson(Map<String, dynamic> json) => Chunk(
        index: (json['index'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        sourceName: json['sourceName'] as String?,
      );
}

class OutlineNode {
  String id;
  String title;
  int depth;
  String status; // generating | done
  List<OutlineNode> children;

  OutlineNode({
    required this.id,
    required this.title,
    required this.depth,
    this.status = 'done',
    List<OutlineNode>? children,
  }) : children = children ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'depth': depth,
        'status': status,
        'children': children.map((e) => e.toJson()).toList(),
      };

  factory OutlineNode.fromJson(Map<String, dynamic> json) => OutlineNode(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        depth: (json['depth'] as num?)?.toInt() ?? 1,
        status: json['status'] as String? ?? 'done',
        children: (json['children'] as List? ?? [])
            .map((e) => OutlineNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

enum QuestionType { single, multi, tf, short }

class Question {
  String id;
  QuestionType type;
  String question;
  List<String> options;
  String answer;
  String explain;
  double difficulty;
  String? citation;

  Question({
    required this.id,
    required this.type,
    required this.question,
    this.options = const [],
    this.answer = '',
    this.explain = '',
    this.difficulty = 0.5,
    this.citation,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'question': question,
        'options': options,
        'answer': answer,
        'explain': explain,
        'difficulty': difficulty,
        'citation': citation,
      };

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        type: QuestionType.values.firstWhere(
            (e) => e.name == json['type'],
            orElse: () => QuestionType.single),
        question: json['question'] as String? ?? '',
        options: (json['options'] as List? ?? []).cast<String>(),
        answer: json['answer'] as String? ?? '',
        explain: json['explain'] as String? ?? '',
        difficulty: (json['difficulty'] as num?)?.toDouble() ?? 0.5,
        citation: json['citation'] as String?,
      );
}

class Mistake {
  String questionId;
  String questionJson;
  String answeredAt;

  Mistake({
    required this.questionId,
    required this.questionJson,
    required this.answeredAt,
  });

  Question get question =>
      Question.fromJson(jsonDecode(questionJson) as Map<String, dynamic>);

  Map<String, dynamic> toJson() =>
      {'questionId': questionId, 'questionJson': questionJson, 'answeredAt': answeredAt};

  factory Mistake.fromJson(Map<String, dynamic> json) => Mistake(
        questionId: json['questionId'] as String,
        questionJson: json['questionJson'] as String,
        answeredAt: json['answeredAt'] as String? ?? '',
      );
}

class ChatMessage {
  String role; // user | model
  String text;
  String createdAt;

  ChatMessage({required this.role, required this.text, required this.createdAt});

  Map<String, dynamic> toJson() =>
      {'role': role, 'text': text, 'createdAt': createdAt};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );
}

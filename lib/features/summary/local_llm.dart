// maeknote — 온디바이스 LLM (llama.cpp via llamadart, GGUF)
import 'package:llamadart/llamadart.dart';

import 'summarizer.dart';

class LocalLlmEngine implements LlmEngine {
  LocalLlmEngine(this.id, this.modelPath, {this.contextSize = 8192});

  @override
  final String id;
  final String modelPath;
  final int contextSize;
  LlamaEngine? _engine;

  Future<LlamaEngine> _load() async => _engine ??= await LlamaEngine.load(
        LlamaModel(ModelSource.path(modelPath)),
        params: ModelParams(contextSize: contextSize),
      );

  @override
  Future<String> complete(String system, String user, {int maxTokens = 1024}) async {
    final engine = await _load();
    return engine
        .create(
          [
            LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
          ],
          params: GenerationParams(maxTokens: maxTokens, temp: 0.3, penalty: 1.05),
          enableThinking: false,
        )
        .text();
  }

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
  }
}

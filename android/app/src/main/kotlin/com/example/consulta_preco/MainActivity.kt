package com.example.consulta_preco

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Recebe backups .db via "Abrir com" (ACTION_VIEW) ou "Compartilhar"
/// (ACTION_SEND), copia o conteúdo para o cache e avisa o Flutter, que
/// abre a tela de importação.
class MainActivity : FlutterActivity() {
    private val canalNome = "consulta_preco/importar"
    private var canal: MethodChannel? = null
    private var arquivoPendente: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalNome)
        canal?.setMethodCallHandler { call, result ->
            when (call.method) {
                // O Flutter pergunta na inicialização se o app foi aberto por um arquivo
                "arquivoPendente" -> {
                    result.success(arquivoPendente)
                    arquivoPendente = null
                }
                else -> result.notImplemented()
            }
        }
        tratarIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App já aberto: avisa o Flutter na hora
        val caminho = extrairArquivo(intent) ?: return
        canal?.invokeMethod("novoArquivo", caminho) ?: run { arquivoPendente = caminho }
    }

    private fun tratarIntent(intent: Intent?) {
        arquivoPendente = extrairArquivo(intent) ?: arquivoPendente
    }

    private fun extrairArquivo(intent: Intent?): String? {
        val uri: Uri? = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            else -> null
        }
        if (uri == null) return null
        return try {
            val destino = File(cacheDir, "backup_recebido.db")
            contentResolver.openInputStream(uri)?.use { entrada ->
                destino.outputStream().use { saida -> entrada.copyTo(saida) }
            } ?: return null
            destino.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}

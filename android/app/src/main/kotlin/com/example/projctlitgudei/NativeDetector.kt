package com.example.projctlitgudei

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * معالج قناة "basira/native_detector" — يشغّل موديل YOLOX-Tiny بكود
 * أندرويد أصلي (Kotlin)، على خيط أندرويد حقيقي منفصل (HandlerThread)،
 * بعيدًا كليًا عن أي تعقيدات Dart Isolates. الهدف: تفادي أي حظر
 * للواجهة أثناء الاستدلال.
 *
 * لا يلمس أي كود Dart قديم — طبقة إضافية بحتة.
 */
class NativeDetector : MethodChannel.MethodCallHandler {

    private var interpreter: Interpreter? = null
    private var outputShape: IntArray = intArrayOf()

    // خيط أندرويد مخصَّص للاستدلال — منفصل تمامًا عن خيط الواجهة
    // (UI thread)، فالاستدلال يشتغل هون بدون ما يأثر على أي رسم/حركة.
    private val workerThread =
        HandlerThread("basira-inference").apply { start() }
    private val workerHandler = Handler(workerThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> loadModel(call, result)
            "runInference" -> runInference(call, result)
            else -> result.notImplemented()
        }
    }

    private fun loadModel(call: MethodCall, result: MethodChannel.Result) {
        workerHandler.post {
            try {
                val modelBytes = call.argument<ByteArray>("modelBytes")
                    ?: throw IllegalArgumentException("modelBytes مفقودة")

                val buffer = ByteBuffer.allocateDirect(modelBytes.size)
                buffer.order(ByteOrder.nativeOrder())
                buffer.put(modelBytes)
                buffer.rewind()

                val options = Interpreter.Options()
                options.setNumThreads(4)
                try {
                    options.setUseXNNPACK(true)
                } catch (e: Throwable) {
                    // بعض إصدارات مكتبة tensorflow-lite ما فيها هذا
                    // الخيار — نتجاهل بأمان ونكمل بدونه.
                }

                val newInterpreter = Interpreter(buffer, options)

                outputShape = newInterpreter.getOutputTensor(0).shape()
                interpreter = newInterpreter

                val response = HashMap<String, Any>()
                response["inputShape"] =
                    newInterpreter.getInputTensor(0).shape().toList()
                response["outputShape"] = outputShape.toList()

                mainHandler.post { result.success(response) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("LOAD_FAILED", e.message, null)
                }
            }
        }
    }

    private fun runInference(call: MethodCall, result: MethodChannel.Result) {
        workerHandler.post {
            try {
                val currentInterpreter = interpreter
                    ?: throw IllegalStateException("الموديل غير محمَّل بعد")

                val inputBytes = call.argument<ByteArray>("input")
                    ?: throw IllegalArgumentException("input مفقودة")

                val inputBuffer = ByteBuffer.allocateDirect(inputBytes.size)
                inputBuffer.order(ByteOrder.nativeOrder())
                inputBuffer.put(inputBytes)
                inputBuffer.rewind()

                val outputElementCount =
                    outputShape.fold(1) { acc, v -> acc * v }
                val outputBuffer =
                    ByteBuffer.allocateDirect(outputElementCount * 4)
                outputBuffer.order(ByteOrder.nativeOrder())

                // الاستدلال الفعلي — يحظر بس هذا الخيط (workerThread)،
                // ما إله أي علاقة بخيط الواجهة إطلاقًا.
                currentInterpreter.run(inputBuffer, outputBuffer)

                outputBuffer.rewind()
                val outputBytes = ByteArray(outputBuffer.remaining())
                outputBuffer.get(outputBytes)

                mainHandler.post { result.success(outputBytes) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("INFERENCE_FAILED", e.message, null)
                }
            }
        }
    }
}
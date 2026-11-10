package com.zavisoft.local_ocr;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.googlecode.tesseract.android.TessBaseAPI;

import java.io.File;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class LocalOcrPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String CHANNEL_NAME = "com.zavisoft.local_ocr";
    private MethodChannel channel;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        BinaryMessenger messenger = flutterPluginBinding.getBinaryMessenger();
        channel = new MethodChannel(messenger, CHANNEL_NAME);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        executor.shutdown();
    }

    @Override
    public void onMethodCall(final MethodCall call, @NonNull final Result result) {
        if ("extractText".equals(call.method) || "extractHocr".equals(call.method)) {
            final boolean returnHocr = "extractHocr".equals(call.method);
            final String tessDataPath = call.argument("tessData");
            final String imagePath = call.argument("imagePath");
            final Map<String, String> args = call.argument("args");
            final String language = call.argument("language") != null ? call.argument("language") : "ben+eng";

            executor.execute(() -> {
                TessBaseAPI baseApi = null;
                try {
                    File imageFile = new File(imagePath);
                    if (!imageFile.exists()) {
                        mainHandler.post(() -> result.error("FILE_NOT_FOUND", "Image file does not exist: " + imagePath, null));
                        return;
                    }

                    baseApi = new TessBaseAPI();
                    boolean initialized = baseApi.init(tessDataPath, language);
                    if (!initialized) {
                        mainHandler.post(() -> result.error("INIT_FAILED", "Failed to initialize Tesseract with language: " + language, null));
                        return;
                    }

                    int psm = TessBaseAPI.PageSegMode.PSM_AUTO_OSD;
                    if (args != null) {
                        for (Map.Entry<String, String> entry : args.entrySet()) {
                            if ("psm".equals(entry.getKey())) {
                                try {
                                    psm = Integer.parseInt(entry.getValue());
                                } catch (NumberFormatException ignored) {}
                            } else {
                                baseApi.setVariable(entry.getKey(), entry.getValue());
                            }
                        }
                    }

                    baseApi.setPageSegMode(psm);
                    baseApi.setImage(imageFile);

                    final String output = returnHocr ? baseApi.getHOCRText(0) : baseApi.getUTF8Text();

                    mainHandler.post(() -> result.success(output != null ? output : ""));
                } catch (Exception e) {
                    mainHandler.post(() -> result.error("OCR_ERROR", e.getMessage(), null));
                } finally {
                    if (baseApi != null) {
                        baseApi.recycle();
                    }
                }
            });
        } else {
            result.notImplemented();
        }
    }
}

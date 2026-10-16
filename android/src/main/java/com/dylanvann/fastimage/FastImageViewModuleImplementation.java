package com.dylanvann.fastimage;

import android.app.Activity;
import android.content.Context;
import android.net.Uri;

import androidx.annotation.NonNull;

import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestBuilder;
import com.bumptech.glide.load.model.GlideUrl;
import com.bumptech.glide.request.FutureTarget;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.views.imagehelper.ImageSource;
import com.facebook.react.bridge.ReactApplicationContext;

import java.io.File;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

class FastImageViewModuleImplementation {
    ReactApplicationContext reactContext;
    FastImageViewModuleImplementation(ReactApplicationContext reactContext){

    this.reactContext = reactContext;
    }

    public static final String REACT_CLASS = "FastImageViewModule";

    // getCachedFile blocks on Glide's future for the whole download; it must
    // neither run on the main thread nor hold the native-modules thread.
    private static final ExecutorService CACHED_FILE_EXECUTOR = Executors.newCachedThreadPool();

    private Activity getCurrentActivity(){
        return reactContext.getCurrentActivity();
    }

    public void preload(final ReadableArray sources) {
        final Activity activity = getCurrentActivity();
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                for (int i = 0; i < sources.size(); i++) {
                    final ReadableMap source = sources.getMap(i);
                    final FastImageSource imageSource = FastImageViewConverter.getImageSource(activity, source);
                    final String sourceUri = source == null || !source.hasKey("uri")
                            ? null
                            : source.getString("uri");
                    if (sourceUri == null || sourceUri.isEmpty()) {
                            System.out.println("Source is null or URI is empty");
                            continue;
                          }
                    // getUri()/getGlideUrl() are nullable when the source resolves to no
                    // usable URI; skip rather than handing Glide a null model.
                    final Object loadModel = imageSource == null
                            ? null
                            : imageSource.isBase64Resource()
                                    ? imageSource.getSource()
                                    : imageSource.isResource()
                                            ? imageSource.getUri()
                                            : imageSource.getGlideUrl();
                    if (loadModel == null) {
                            continue;
                          }
                    Glide
                            .with(activity.getApplicationContext())
                            // This will make this work for remote and local images. e.g.
                            //    - file:///
                            //    - content://
                            //    - res:/
                            //    - android.resource://
                            //    - data:image/png;base64
                            .load(loadModel)
                            .apply(FastImageViewConverter.getOptions(activity, imageSource, source, null))
                            .preload();
                }
            }
        });
    }

    public void clearMemoryCache(final Promise promise) {
        final Activity activity = getCurrentActivity();
        if (activity == null) {
            promise.resolve(null);
            return;
        }

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Glide.get(activity.getApplicationContext()).clearMemory();
                promise.resolve(null);
            }
        });
    }
    public void getCachedFile(final ReadableMap source, final Promise promise) {
        final String uri = source != null && source.hasKey("uri") && !source.isNull("uri")
                ? source.getString("uri")
                : null;
        if (uri == null || uri.isEmpty()) {
            promise.reject("E_INVALID_SOURCE", "getCachedFile: the source has no uri");
            return;
        }
        final Context appContext = reactContext.getApplicationContext();
        CACHED_FILE_EXECUTOR.execute(new Runnable() {
            @Override
            public void run() {
                try {
                    resolveCachedFile(appContext, source, uri, promise);
                } catch (Throwable error) {
                    promise.reject("E_LOAD_FAILED", "getCachedFile: " + error.getMessage(), error);
                }
            }
        });
    }

    private static void resolveCachedFile(
            Context appContext, ReadableMap source, String uri, Promise promise) {
        // A bare path has no scheme, and ImageSource would look it up as a
        // bundled resource name.
        if (uri.startsWith("/")) {
            resolveLocalFile(new File(uri), promise);
            return;
        }

        final FastImageSource imageSource = FastImageViewConverter.getImageSource(appContext, source);
        final Uri sourceUri = imageSource == null ? null : imageSource.getUri();
        if (sourceUri == null) {
            promise.reject("E_INVALID_SOURCE", "getCachedFile: the uri cannot be resolved");
            return;
        }
        if (imageSource.isLocalFile()) {
            final String path = sourceUri.getPath();
            if (path == null) {
                promise.reject("E_INVALID_SOURCE", "getCachedFile: the file uri has no path");
                return;
            }
            resolveLocalFile(new File(path), promise);
            return;
        }
        final String scheme = sourceUri.getScheme();
        if (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)) {
            promise.reject("E_UNSUPPORTED_SOURCE", "getCachedFile: unsupported uri scheme '" + scheme + "'");
            return;
        }

        // The view's own model: same GlideUrl, the cache tier carried in it, so
        // the same DataCacheKey and the same tier's disk cache.
        final GlideUrl glideUrl = imageSource.getGlideUrl();
        final boolean isVideo = source.hasKey("isVideo")
                && !source.isNull("isVideo")
                && source.getBoolean("isVideo");
        // A video goes through FastImageVideoFrameLoader, which caches a frame,
        // not the file.
        if (glideUrl == null || isVideo || FastImageVideoFrameLoader.isVideoUrl(glideUrl)) {
            promise.reject("E_UNSUPPORTED_SOURCE", "getCachedFile: video sources are not supported");
            return;
        }

        final boolean cacheOnly =
                FastImageViewConverter.getCacheControl(source) == FastImageCacheControl.CACHE_ONLY;
        // downloadOnly() caches DATA: the original bytes under the same key
        // AUTOMATIC uses for a remote source, so a file the view already
        // fetched is a disk hit. It does not join a view load still in flight:
        // the engine keys differ (File vs Drawable, size, transformations).
        RequestBuilder<File> request = Glide.with(appContext)
                .downloadOnly()
                .load(glideUrl)
                .priority(FastImageViewConverter.getPriority(source));
        if (cacheOnly) {
            request = request.onlyRetrieveFromCache(true);
        }
        final FutureTarget<File> future = request.submit();
        try {
            final File file = future.get();
            if (file == null || !file.exists()) {
                promise.reject("E_LOAD_FAILED", "getCachedFile: the loaded image was not stored on disk");
                return;
            }
            promise.resolve(file.getAbsolutePath());
        } catch (ExecutionException error) {
            final Throwable cause = error.getCause() == null ? error : error.getCause();
            promise.reject(
                    cacheOnly ? "E_NOT_CACHED" : "E_LOAD_FAILED",
                    "getCachedFile: " + cause.getMessage(),
                    cause);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            promise.reject("E_LOAD_FAILED", "getCachedFile: interrupted", error);
        } finally {
            Glide.with(appContext).clear(future);
        }
    }

    private static void resolveLocalFile(File file, Promise promise) {
        if (file.exists()) {
            promise.resolve(file.getAbsolutePath());
        } else {
            promise.reject("E_LOAD_FAILED", "getCachedFile: no file at " + file.getAbsolutePath());
        }
    }

    public void clearDiskCache(Promise promise) {
        final Activity activity = getCurrentActivity();
        if (activity == null) {
            promise.resolve(null);
            return;
        }

        Glide.get(activity.getApplicationContext()).clearDiskCache();
        promise.resolve(null);
    }
}

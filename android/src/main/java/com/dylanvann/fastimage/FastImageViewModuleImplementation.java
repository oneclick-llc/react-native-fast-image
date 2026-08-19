package com.dylanvann.fastimage;

import android.app.Activity;

import androidx.annotation.NonNull;

import com.bumptech.glide.Glide;
import com.bumptech.glide.load.model.GlideUrl;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.views.imagehelper.ImageSource;
import com.facebook.react.bridge.ReactApplicationContext;

class FastImageViewModuleImplementation {
    ReactApplicationContext reactContext;
    FastImageViewModuleImplementation(ReactApplicationContext reactContext){

    this.reactContext = reactContext;
    }

    public static final String REACT_CLASS = "FastImageViewModule";

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

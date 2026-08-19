package com.dylanvann.fastimage;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.drawable.Drawable;
import android.net.Uri;

import androidx.annotation.Nullable;
import androidx.annotation.NonNull;
import androidx.appcompat.widget.AppCompatImageView;

import com.bumptech.glide.RequestBuilder;
import com.bumptech.glide.RequestManager;
import com.bumptech.glide.load.model.GlideUrl;
import com.bumptech.glide.request.Request;
import com.bumptech.glide.load.resource.drawable.DrawableTransitionOptions;
import com.bumptech.glide.load.resource.gif.GifDrawable;
import com.facebook.react.bridge.ReadableMap;
import com.dylanvann.fastimage.events.FastImageErrorEvent;
import com.dylanvann.fastimage.events.FastImageLoadStartEvent;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.UIManagerHelper;
import com.facebook.react.uimanager.events.EventDispatcher;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import android.os.Build;
import android.util.Log;

class FastImageViewWithUrl extends AppCompatImageView {
    private static final String TAG = "FastImageViewWithUrl";
    private boolean mNeedsReload = false;
    private ReadableMap mSource = null;
    private Drawable mDefaultSource = null;
    private int mBlurRadius = 0;
    private int mBlurRadiusPrevious = 0;
    // В какой размер (в пикселях) распаковывать картинку. Ноль — как раньше.
    private int mResizeWidth = 0;
    private int mResizeHeight = 0;
    public GlideUrl glideUrl;
    private String mTransition = "none"; // "none" | "fade"

    public FastImageViewWithUrl(Context context) {
        super(context);
    }

    public void setSource(@Nullable ReadableMap source) {
        mNeedsReload = true;
        mSource = source;
    }

    public void setDefaultSource(@Nullable Drawable source) {
        mNeedsReload = true;
        mDefaultSource = source;
    }

    public void setBlurRadius(@Nullable Integer blurRadius) {
        mNeedsReload = true;
        mBlurRadiusPrevious = mBlurRadius;
        mBlurRadius = blurRadius == null ? 0 : blurRadius;
    }

    /**
     * Размер декодирования в пикселях.
     *
     * Glide и сам умеет считать размер по вью, в которую грузит, но полагаться
     * на это нельзя: вью может быть ещё не измерена в момент запроса, а
     * `wrap_content` он трактует как «во весь экран». Явный `override` убирает
     * это гадание — снимок 5000×5000 распаковывается в те пиксели, что реально
     * видны, а не в 95 МБ битмапа.
     */
    public void setResizeSize(@Nullable ReadableMap resizeSize) {
        mNeedsReload = true;
        if (resizeSize == null) {
            mResizeWidth = 0;
            mResizeHeight = 0;
            return;
        }
        mResizeWidth = resizeSize.hasKey("width")
                ? (int) Math.round(resizeSize.getDouble("width"))
                : 0;
        mResizeHeight = resizeSize.hasKey("height")
                ? (int) Math.round(resizeSize.getDouble("height"))
                : 0;
    }

    public void setTransition(@Nullable String transition) {
        mNeedsReload = true;
        if (transition == null) {
            mTransition = "none";
        } else {
            mTransition = transition;
        }
    }

    /**
     * Renders the JS-side source for diagnostics without dereferencing anything nullable.
     */
    private static String describeSource(@Nullable ReadableMap source) {
        if (source == null) {
            return "source=null";
        }
        // Diagnostics must never throw: the callers are already error paths, and
        // getString() raises if the value is not actually a string.
        try {
            String uri = source.hasKey("uri") ? source.getString("uri") : null;
            String tier = source.hasKey("cacheTier") ? source.getString("cacheTier") : null;
            return "uri=" + (uri == null ? "null" : "'" + uri + "'")
                    + ", cacheTier=" + (tier == null ? "null" : "'" + tier + "'");
        } catch (Exception e) {
            return "source=<undescribable: " + e.getClass().getSimpleName() + ">";
        }
    }

    private boolean isNullOrEmpty(final String url) {
        return url == null || url.trim().isEmpty();
    }

    /**
     * Модель для Glide — обычная, а «это видео» запоминается рядом.
     *
     * По расширению загрузчик кадров узнаёт видео сам; признак нужен для
     * ссылок без расширения. Менять из-за него саму модель нельзя: она входит
     * в ключ запроса, и тогда одна и та же ссылка с признаком и без него
     * читалась бы дважды.
     */
    @Nullable
    private Object sourceForLoad(@Nullable FastImageSource imageSource) {
        if (imageSource == null) {
            return null;
        }
        boolean isVideo = mSource != null
                && mSource.hasKey("isVideo")
                && !mSource.isNull("isVideo")
                && mSource.getBoolean("isVideo");
        Uri sourceUri = imageSource.getUri();
        if (isVideo && sourceUri != null) {
            FastImageVideoUrl.remember(sourceUri.toString());
        }
        return imageSource.getSourceForLoad();
    }

    @SuppressLint("CheckResult")
    public void onAfterUpdate(
            @NonNull FastImageViewManager manager,
            @Nullable RequestManager requestManager,
            @NonNull Map<String, List<FastImageViewWithUrl>> viewsForUrlsMap) {
        if (!mNeedsReload)
            return;

        if ((mSource == null ||
                !mSource.hasKey("uri") ||
                isNullOrEmpty(mSource.getString("uri"))) &&
                mDefaultSource == null) {

            // Cancel existing requests.
            clearView(requestManager);

            if (glideUrl != null) {
                FastImageOkHttpProgressGlideModule.forget(glideUrl.toStringUrl());
            }

            // Clear the image.
            setImageDrawable(null);

            ThemedReactContext context = (ThemedReactContext) getContext();
            EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
            int surfaceId = UIManagerHelper.getSurfaceId(this);
            FastImageErrorEvent event = new FastImageErrorEvent(surfaceId, getId(), mSource);
            if (dispatcher != null) {
                dispatcher.dispatchEvent(event);
            }
            return;
        }

        //final GlideUrl glideUrl = FastImageViewConverter.getGlideUrl(view.getContext(), mSource);
        final FastImageSource imageSource = FastImageViewConverter.getImageSource(getContext(), mSource);

        // `getUri()` is nullable: FastImageSource#resolveResourceUri yields null when the
        // source has no scheme and matches neither a drawable nor a raw resource. Treat that
        // exactly like the long-standing empty-URI case instead of dereferencing it.
        final Uri imageSourceUri = imageSource == null ? null : imageSource.getUri();
        if (imageSource != null && (imageSourceUri == null || imageSourceUri.toString().length() == 0)) {
            if (imageSourceUri == null) {
                Log.w(TAG, "Unusable image source (no resolvable URI): " + describeSource(mSource));
            }
            ThemedReactContext context = (ThemedReactContext) getContext();
            EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
            int surfaceId = UIManagerHelper.getSurfaceId(this);
            FastImageErrorEvent event = new FastImageErrorEvent(surfaceId, getId(), mSource);

            if (dispatcher != null) {
                dispatcher.dispatchEvent(event);
            }
            // Cancel existing requests.
            clearView(requestManager);

            if (glideUrl != null) {
                FastImageOkHttpProgressGlideModule.forget(glideUrl.toStringUrl());
            }
            // Clear the image.
            setImageDrawable(null);
            return;
        }

        // `imageSource` may be null and we still continue, if `defaultSource` is not null
        final GlideUrl glideUrl = imageSource == null ? null : imageSource.getGlideUrl();

        // Cancel existing request.
        this.glideUrl = glideUrl;
        clearView(requestManager);

        String key = glideUrl == null ? null : glideUrl.toStringUrl();

        if (glideUrl != null) {
            FastImageOkHttpProgressGlideModule.expect(key, manager);
            List<FastImageViewWithUrl> viewsForKey = viewsForUrlsMap.get(key);
            if (viewsForKey != null && !viewsForKey.contains(this)) {
                viewsForKey.add(this);
            } else if (viewsForKey == null) {
                List<FastImageViewWithUrl> newViewsForKeys = new ArrayList<>(Collections.singletonList(this));
                viewsForUrlsMap.put(key, newViewsForKeys);
            }
        }

        ThemedReactContext context = (ThemedReactContext) getContext();
        if (imageSource != null) {
            // This is an orphan even without a load/loadend when only loading a placeholder
            // This is an orphan event without a load/loadend when only loading a placeholder
            EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
            int surfaceId = UIManagerHelper.getSurfaceId(this);
            FastImageLoadStartEvent event = new FastImageLoadStartEvent(surfaceId, getId());

            if (dispatcher != null) {
                dispatcher.dispatchEvent(event);
            }
        }

        if (requestManager != null) {
            RequestBuilder<? extends Drawable> builder;
            Map<String, Object> builderOptions = new HashMap<>();
            builderOptions.put("view", this);
            builderOptions.put("blurRadius", mBlurRadius);
            builderOptions.put("blurRadiusShouldClean", mBlurRadiusPrevious > 0 && mBlurRadius <= 0);

            try {
                builder = requestManager
                        .load(sourceForLoad(imageSource))
                        .apply(FastImageViewConverter
                                .getOptions(context, imageSource, mSource, builderOptions)
                                .placeholder(mDefaultSource) // show until loaded
                                .fallback(mDefaultSource)); // null will not be treated as error

                if (mResizeWidth > 0 && mResizeHeight > 0) {
                    builder = builder.override(mResizeWidth, mResizeHeight);
                }

                if (key != null) {
                    builder.listener(new FastImageRequestListener(key));
                }

                if ("fade".equals(mTransition)) {
                    builder = builder.transition(DrawableTransitionOptions.withCrossFade());
                }

                builder.into(this);
            } catch (Exception e) {
                Log.e(TAG, String.format("Error detecting image type for URI: %s. Exception: %s",
                describeSource(mSource), e.getMessage()), e);
            }
        }
    }

    public void clearView(@Nullable RequestManager requestManager) {
        if (requestManager != null && getTag() != null && getTag() instanceof Request) {
            requestManager.clear(this);
        }
    }
}

package com.dylanvann.fastimage;

import android.content.Context;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.UiContext;

import com.bumptech.glide.request.RequestOptions;

import java.util.Map;

class FastImageBlurHelper {

    static RequestOptions transform(
            @NonNull @UiContext Context context,
            @NonNull RequestOptions options,
            @Nullable Map<String, Object> imageOptions
    ) {
        if (imageOptions == null) return options;

        ImageView view = getImageView(imageOptions.get("view"));

        if (view == null) return options;

        int blurRadius = getInt(imageOptions.get("blurRadius"));
        boolean blurRadiusShouldClean = getBoolean(imageOptions.get("blurRadiusShouldClean"));

        if (blurRadiusShouldClean) {
            FastImageBlurTransformation.clean(view);
        }

        if (blurRadius > 0) {
            return options.transform(new FastImageBlurTransformation(context, blurRadius, view));
        }

        return options;
    }

    @Nullable
    private static ImageView getImageView(@Nullable Object value) {
        return (value instanceof ImageView) ? (ImageView) value : null;
    }

    private static int getInt(@Nullable Object value) {
        return (value instanceof Number) ? ((Number) value).intValue() : 0;
    }

    private static boolean getBoolean(@Nullable Object value) {
        return (value instanceof Boolean) && (Boolean) value;
    }
}

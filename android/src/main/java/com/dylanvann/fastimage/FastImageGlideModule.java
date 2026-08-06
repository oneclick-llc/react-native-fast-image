package com.dylanvann.fastimage;

import android.content.Context;
import android.graphics.Bitmap;

import androidx.annotation.NonNull;

import com.bumptech.glide.Glide;
import com.bumptech.glide.GlideBuilder;
import com.bumptech.glide.Registry;
import com.bumptech.glide.annotation.GlideModule;
import com.bumptech.glide.load.model.GlideUrl;
import com.bumptech.glide.module.AppGlideModule;

// We need an AppGlideModule to be present for progress events to work.
@GlideModule
public final class FastImageGlideModule extends AppGlideModule {
    @Override
    public void applyOptions(@NonNull Context context, @NonNull GlideBuilder builder) {
        builder.setDiskCache(new ExtraDiskCacheAdapter.Factory(context));
    }

    @Override
    public void registerComponents(@NonNull Context context, @NonNull Glide glide, @NonNull Registry registry) {
        // `prepend`, а не `append`: ссылку на видео качалка тоже возьмёт себе —
        // и потянет ролик целиком, чтобы отдать его декодеру картинок. Наш
        // загрузчик должен получить её первым, а всё остальное он пропускает
        // мимо (`handles`).
        registry.prepend(GlideUrl.class, Bitmap.class, new FastImageVideoFrameLoader.Factory());
        // Кадр приезжает уже картинкой, и без этого Glide не может положить его
        // на диск — а не сумев, роняет всю загрузку.
        registry.append(Bitmap.class, new FastImageBitmapEncoder());
    }
}

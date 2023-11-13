package com.dylanvann.fastimage;

import android.content.Context;

import androidx.annotation.NonNull;

import com.bumptech.glide.GlideBuilder;
import com.bumptech.glide.annotation.GlideModule;
import com.bumptech.glide.module.AppGlideModule;

// We need an AppGlideModule to be present for progress events to work.
@GlideModule
public final class FastImageGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(@NonNull Context context, @NonNull GlideBuilder builder) {
    builder.setDiskCache(new ExtraDiskCacheAdapter.Factory(context));
  }
}

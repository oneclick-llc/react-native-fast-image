package com.dylanvann.fastimage;

import android.graphics.Bitmap;

import androidx.annotation.NonNull;

import com.bumptech.glide.load.Encoder;
import com.bumptech.glide.load.Options;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

/**
 * Чем записать на диск то, что пришло от загрузчика уже картинкой.
 *
 * Кадр из видео приезжает готовым Bitmap, а не потоком байтов, и Glide на
 * попытке положить его в кэш отвечает `NoSourceEncoderAvailableException` —
 * то есть загрузка падает целиком, хотя кадр уже получен. Кодировщиков для
 * Bitmap как ИСХОДНЫХ данных у него нет: обычно исходные данные — это поток.
 */
public class FastImageBitmapEncoder implements Encoder<Bitmap> {

    private static final int QUALITY = 90;

    @Override
    public boolean encode(@NonNull Bitmap data, @NonNull File file, @NonNull Options options) {
        try (OutputStream out = new FileOutputStream(file)) {
            // JPEG, а не PNG: кадр из видео фотографичен, и PNG на нём — это
            // втрое больше места без единого лишнего различимого пикселя.
            return data.compress(Bitmap.CompressFormat.JPEG, QUALITY, out);
        } catch (Throwable error) {
            return false;
        }
    }
}

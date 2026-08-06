import React from 'react';
import {Text} from 'react-native';

interface IconProps {
  size?: number;
  name: string;
  color: string;
}

/**
 * Значки вкладок эмодзи, а не шрифтом.
 *
 * Раньше здесь стоял react-native-vector-icons: ради трёх картинок в таб-баре
 * он тянет шрифты, их регистрацию в Info.plist и свою сборку под каждую
 * платформу. Пример существует, чтобы проверять картинки, — лишняя нативная
 * зависимость в нём только мешает поднять его на новой версии RN.
 */
const GLYPHS: Record<string, string> = {
  'information-circle-outline': 'ℹ️',
  'image-outline': '🖼️',
  'images-outline': '🗂️',
};

export function Icon({size = 24, name, color}: IconProps) {
  return (
    <Text style={{fontSize: size, lineHeight: size + 2, color}}>
      {GLYPHS[name] ?? '•'}
    </Text>
  );
}

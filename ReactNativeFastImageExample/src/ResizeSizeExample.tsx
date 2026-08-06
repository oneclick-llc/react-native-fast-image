import React, {useState} from 'react';
import {PixelRatio, Platform, StyleSheet, Text, View} from 'react-native';
import FastImage from 'react-native-fast-image';
import Section from './Section';
import SectionFlex from './SectionFlex';
import FeatureText from './FeatureText';
import BulletText from './BulletText';
import Button from './Button';
import {useCacheBust} from './useCacheBust';

/**
 * Стенд для `resizeSize`: в какой размер картинка РАСПАКОВЫВАЕТСЯ.
 *
 * Разницу глазами не видно — обе плитки выглядят одинаково, — поэтому под
 * каждой написан размер, который вернуло событие `onLoad`. Это и есть размер
 * распакованной картинки: на iOS `image.size` уже после трансформера
 * SDWebImage, на Android `getIntrinsicWidth/Height` у того, что отдал Glide.
 *
 * Что получается на самом деле, и платформы ведут себя по-разному:
 *
 *   iOS      — без пропа 4000×3000, с пропом размер плитки. SDWebImage
 *              разворачивает оригинал целиком, пока ему не сказали иначе;
 *   Android  — ОБА числа примерно с плитку. Glide и сам считает размер по
 *              вью, в которую грузит, поэтому здесь проп ничего не меняет.
 *              Он нужен там, где считать не по чему: вью ещё не измерена в
 *              момент запроса или растянута флексом.
 *
 * До правки Android-половины оба числа тоже совпадали — но потому, что проп
 * доходил до нативной стороны и выбрасывался (`resizeSize is not supported on
 * Android` в логах). Разницу между «работает» и «выброшен» на этом экране не
 * видно; она видна в логе и в том, что вью без измерения получает размер.
 */
const IMAGE_URL = 'https://picsum.photos/id/1015/4000/3000';

const TILE = 100;
const DECODE = {
  width: PixelRatio.getPixelSizeForLayoutSize(TILE),
  height: PixelRatio.getPixelSizeForLayoutSize(TILE),
};

interface TileProps {
  url: string;
  label: string;
  resizeSize?: {width: number; height: number};
}

const Tile = ({url, label, resizeSize}: TileProps) => {
  const [decoded, setDecoded] = useState<string>('…');

  return (
    <View style={styles.tile}>
      <FastImage
        style={styles.image}
        source={{uri: url}}
        resizeSize={resizeSize}
        onLoad={e =>
          setDecoded(`${e.nativeEvent.width}×${e.nativeEvent.height}`)
        }
        onError={() => setDecoded('ошибка')}
      />
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{decoded}</Text>
    </View>
  );
};

export const ResizeSizeExample = () => {
  const {url, bust} = useCacheBust(IMAGE_URL);

  return (
    <View>
      <Section>
        <FeatureText text="• resizeSize: размер распаковки в пикселях." />
        <BulletText
          text={`Оригинал 4000×3000, плитка ${TILE}pt. Под плиткой — размер, который вернул onLoad.`}
        />
        <BulletText
          text={
            Platform.OS === 'android'
              ? 'Android: числа совпадают и это норма — Glide сам считает размер по вью. Проп нужен, когда считать не по чему.'
              : 'iOS: правая плитка должна быть заметно меньше левой.'
          }
        />
      </Section>
      <SectionFlex style={styles.section}>
        <Tile url={url} label="без resizeSize" />
        <Tile
          url={url}
          label={`resizeSize ${DECODE.width}×${DECODE.height}`}
          resizeSize={DECODE}
        />
      </SectionFlex>
      <SectionFlex style={styles.buttons}>
        <Button text="Bust" onPress={bust} />
      </SectionFlex>
    </View>
  );
};

const styles = StyleSheet.create({
  section: {
    justifyContent: 'space-around',
    paddingVertical: 10,
  },
  buttons: {
    justifyContent: 'center',
    paddingBottom: 10,
  },
  tile: {
    alignItems: 'center',
  },
  image: {
    width: TILE,
    height: TILE,
    backgroundColor: '#ddd',
  },
  label: {
    marginTop: 6,
    fontSize: 11,
    color: '#666',
  },
  value: {
    fontSize: 13,
    fontWeight: '700',
    color: '#222',
  },
});

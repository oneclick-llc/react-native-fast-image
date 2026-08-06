import React from 'react';
import {StyleSheet, View} from 'react-native';
import SectionFlex from './SectionFlex';
import FastImage from 'react-native-fast-image';
import Section from './Section';
import FeatureText from './FeatureText';
import {useCacheBust} from './useCacheBust';

const SVG_URL =
  'https://raw.githubusercontent.com/dream-sports-labs/react-native-fast-image/4ca19207372f0c435660bba4307e0a3318719e42/ReactNativeFastImageExampleServer/pictures/react-native.svg';

export const SvgExample = () => {
  const {url, bust} = useCacheBust(SVG_URL);
  return (
    <View>
      <Section>
        <FeatureText text="• SVG support." />
      </Section>
      <SectionFlex onPress={bust}>
        <FastImage style={styles.image} source={{uri: url}} />
      </SectionFlex>
    </View>
  );
};

const styles = StyleSheet.create({
  image: {
    backgroundColor: '#ddd',
    margin: 20,
    height: 100,
    width: 100,
    flex: 0,
  },
});

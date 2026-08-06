import React from 'react';
import {StyleSheet, View} from 'react-native';
import FastImage from 'react-native-fast-image';
import Section from './Section';
import SectionFlex from './SectionFlex';
import FeatureText from './FeatureText';

// @ts-ignore
import FieldsImage from './images/fields.jpg';

export const BlurRadiusExample = () => {
  return (
    <View>
      <Section>
        <FeatureText text="• Images with blur radius." />
      </Section>
      <SectionFlex>
        <View style={styles.imageField}>
          <FastImage style={styles.image} source={FieldsImage} />
        </View>

        <View style={styles.imageField}>
          <FastImage style={styles.image} source={FieldsImage} blurRadius={10} />
        </View>

        <View style={styles.imageField}>
          <FastImage
            style={styles.image}
            source={FieldsImage}
            blurRadius={30}
          />
        </View>
      </SectionFlex>
    </View>
  );
};

const styles = StyleSheet.create({
  imageField: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    margin: 10,
  },
  image: {
    width: 80,
    height: 80,
  },
});

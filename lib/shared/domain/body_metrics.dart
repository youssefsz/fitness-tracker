import 'dart:typed_data';

const maxDisplayName = 60;
const maxHeightMillimeters = 3000;
const maxWeightGrams = 1000000;
const maxProfilePhotoBytes = 1024 * 1024;

enum AvatarPreset {
  anonymous('Default'),
  running('Running'),
  strength('Strength'),
  mobility('Mobility');

  const AvatarPreset(this.label);

  final String label;
}

enum HeightUnit {
  cm('Centimeters', 'cm'),
  ftIn('Feet and inches', 'ft / in');

  const HeightUnit(this.label, this.symbol);

  final String label;
  final String symbol;
}

const inchesPerFoot = 12;
const millimetersPerInch = 25.4;

({int feet, double inches}) heightInFeetAndInches(int millimeters) {
  // Round before splitting so the inches part never displays as 12.
  final hundredths = (millimeters * 100 / millimetersPerInch).round();
  return (
    feet: hundredths ~/ (inchesPerFoot * 100),
    inches: (hundredths % (inchesPerFoot * 100)) / 100,
  );
}

enum WeightUnit {
  kg('Kilograms', 1000, 3),
  lb('Pounds', 453.59237, 2);

  const WeightUnit(this.label, this.grams, this.decimals);

  final String label;
  final double grams;
  // Whole-gram storage round-trips pound values to two decimal places.
  final int decimals;
}

typedef ProfileDetails = ({
  String? displayName,
  int? heightMillimeters,
  HeightUnit heightUnit,
  WeightUnit weightUnit,
});

const ProfileDetails defaultProfileDetails = (
  displayName: null,
  heightMillimeters: null,
  heightUnit: HeightUnit.cm,
  weightUnit: WeightUnit.kg,
);

class LocalProfile {
  const LocalProfile(this.details, this.photo, this.avatarPreset);

  final ProfileDetails details;
  final Uint8List? photo;
  final AvatarPreset avatarPreset;
}

String? displayNameError(String name) {
  if (name.trim().length > maxDisplayName) {
    return 'Use $maxDisplayName characters or fewer.';
  }
  if (name.codeUnits.any((unit) => unit < 32 || unit == 127)) {
    return 'Use a single line.';
  }
  return null;
}

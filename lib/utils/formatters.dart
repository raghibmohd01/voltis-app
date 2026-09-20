String formatPower(double watts) =>
    watts >= 1000 ? '${(watts / 1000).toStringAsFixed(2)} kW' : '${watts.toStringAsFixed(0)} W';

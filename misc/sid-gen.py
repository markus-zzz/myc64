def gentable(freq, values):
  period = 1.0 / freq

  idx = 0
  for value in values:
    print('  4\'h' + format(idx, 'x') + ': res = ' + '17\'h' + format(int((value / period) / 256), 'x') + ';  // ' + str(value))
    idx = idx + 1

print('\nDecay & Relase length values:\n')
gentable(1e6, [0.006, 0.024, 0.048, 0.072, 0.114, 0.168, 0.204, 0.240, 0.300, 0.750, 1.500, 2.400, 3.000, 9.000, 15.000, 24.000])
print('\nAttack length values:\n')
gentable(1e6, [0.002, 0.008, 0.016, 0.024, 0.038, 0.056, 0.068, 0.080, 0.100, 0.250, 0.500, 0.800, 1.000, 3.000, 5.000, 8.000])

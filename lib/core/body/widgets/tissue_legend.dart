import 'package:flutter/material.dart';
import '../models/body_region.dart';

class TissueLegend extends StatelessWidget {
  const TissueLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: TissueType.values.map((t) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: tissueColors[t],
                shape: t == TissueType.joint
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                borderRadius: t != TissueType.joint
                    ? BorderRadius.circular(3)
                    : null,
                border: Border.all(color: tissueDarkColors[t]!, width: 1.5),
              ),
            ),
            const SizedBox(width: 4),
            Text(tissueLabels[t]!, style: const TextStyle(fontSize: 12)),
          ],
        );
      }).toList(),
    );
  }
}

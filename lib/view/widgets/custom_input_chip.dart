import 'package:flutter/material.dart';
class HoverChip extends StatefulWidget {
  final String text;
  final Color color;
  final VoidCallback onDelete;

  const HoverChip({
    super.key,
    required this.text,
    required this.color,
    required this.onDelete,
  });

  @override
  _HoverChipState createState() => _HoverChipState();
}

class _HoverChipState extends State<HoverChip> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
       Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
   color: widget.color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(5),
    border: Border.all(
     
      width: .5,
    ),
  ),
  child: Text(
    widget.text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    
    ),
  ),
)
,

          if (isHovered)
            Positioned(
              right: -6,
              top: -6,
              child: InkWell(
                onTap: widget.onDelete,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

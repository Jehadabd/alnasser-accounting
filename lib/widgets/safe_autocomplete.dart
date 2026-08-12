import 'package:flutter/material.dart';

/// A safer implementation of Autocomplete that prevents the "_zOrderIndex != null"
/// assertion error when multiple Autocomplete widgets are used in the same screen.
/// 
/// This implementation uses a custom controller to manage the overlay state and
/// properly dispose of it when the widget is removed from the tree.
class SafeAutocomplete<T extends Object> extends StatefulWidget {
  final AutocompleteOptionsBuilder<T> optionsBuilder;
  final AutocompleteOnSelected<T>? onSelected;
  final AutocompleteFieldViewBuilder fieldViewBuilder;
  final AutocompleteOptionsViewBuilder<T>? optionsViewBuilder;
  final AutocompleteOptionToString<T> displayStringForOption;
  final TextEditingValue? initialValue;

  const SafeAutocomplete({
    Key? key,
    required this.optionsBuilder,
    this.onSelected,
    required this.fieldViewBuilder,
    this.optionsViewBuilder,
    this.displayStringForOption = RawAutocomplete.defaultStringForOption,
    this.initialValue,
  }) : super(key: key);

  @override
  State<SafeAutocomplete<T>> createState() => _SafeAutocompleteState<T>();
}

class _SafeAutocompleteState<T extends Object> extends State<SafeAutocomplete<T>> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  
  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }
  
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Autocomplete<T>(
        optionsBuilder: widget.optionsBuilder,
        onSelected: (T selection) {
          _removeOverlay();
          if (widget.onSelected != null) {
            widget.onSelected!(selection);
          }
        },
        fieldViewBuilder: widget.fieldViewBuilder,
        optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<T> onSelected, Iterable<T> options) {
          if (_overlayEntry != null) {
            _removeOverlay();
          }
          
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          final Size size = renderBox.size;
          
          // حساب العرض المناسب للقائمة المنسدلة
          // الحد الأدنى 300 بكسل لعرض أسماء المنتجات الطويلة
          final double dropdownWidth = size.width < 300 ? 300.0 : size.width;
          
          _overlayEntry = OverlayEntry(
            builder: (BuildContext context) {
              return Positioned(
                width: dropdownWidth,
                child: CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  offset: Offset(0.0, size.height),
                  child: _AutocompleteOptions<T>(
                    displayStringForOption: widget.displayStringForOption,
                    onSelected: (T selection) {
                      _removeOverlay();
                      onSelected(selection);
                    },
                    options: options,
                  ),
                ),
              );
            },
          );
          
          Overlay.of(context).insert(_overlayEntry!);
          
          return Container();
        },
        displayStringForOption: widget.displayStringForOption,
      ),
    );
  }
}

/// A custom implementation of the options widget that properly handles
/// overlay disposal to prevent assertion errors.
class _AutocompleteOptions<T extends Object> extends StatelessWidget {
  final AutocompleteOnSelected<T> onSelected;
  final Iterable<T> options;
  final AutocompleteOptionToString<T> displayStringForOption;

  const _AutocompleteOptions({
    required this.onSelected,
    required this.options,
    required this.displayStringForOption,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4.0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (BuildContext context, int index) {
            final T option = options.elementAt(index);
            return InkWell(
              onTap: () {
                onSelected(option);
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(displayStringForOption(option)),
              ),
            );
          },
        ),
      ),
    );
  }
}
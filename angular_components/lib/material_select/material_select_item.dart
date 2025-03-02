// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:html';

import 'package:angular/angular.dart';
import 'package:angular_components/button_decorator/button_decorator.dart';
import 'package:angular_components/dynamic_component/dynamic_component.dart';
import 'package:angular_components/glyph/glyph.dart';
import 'package:angular_components/interfaces/has_disabled.dart';
import 'package:angular_components/material_checkbox/material_checkbox.dart';
import 'package:angular_components/material_select/activation_handler.dart';
import 'package:angular_components/mixins/material_dropdown_base.dart';
import 'package:angular_components/model/selection/selection_container.dart';
import 'package:angular_components/model/selection/selection_model.dart';
import 'package:angular_components/model/ui/has_factory.dart';
import 'package:angular_components/utils/disposer/disposer.dart';

/// Material Select Item is a special kind of list item which can be selected.
///
/// For accessibility, should be contained in an element with role="listbox" and
/// aria-multiselectable set appropriately, unless [role] is set to something
/// other than "option".
@Component(
  selector: 'material-select-item',
  providers: [
    ExistingProvider(SelectionItem, MaterialSelectItemComponent),
    ExistingProvider(HasDisabled, MaterialSelectItemComponent),
    ExistingProvider(HasRenderer, MaterialSelectItemComponent),
  ],
  styleUrls: ['material_select_item.scss.css'],
  directives: [
    GlyphComponent,
    MaterialCheckboxComponent,
    NgIf,
    DynamicComponent
  ],
  templateUrl: 'material_select_item.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
)
class MaterialSelectItemComponent<T> extends ButtonDirective
    implements
        OnDestroy,
        SelectionItem<T>,
        HasRenderer<T>,
        HasComponentRenderer,
        HasFactoryRenderer<RendersValue, T> {
  @HostBinding('class')
  static const hostClass = 'item';

  final _disposer = Disposer.oneShot();
  final ActivationHandler _activationHandler;
  final ChangeDetectorRef _cdRef;
  final DropdownHandle _dropdown;

  final HtmlElement element;

  StreamSubscription _selectionChangeStreamSub;

  MaterialSelectItemComponent(
      this.element,
      @Optional() this._dropdown,
      @Optional() this._activationHandler,
      this._cdRef,
      @Attribute('role') String role,
      {bool addTabIndexWhenNonTabbable = false})
      : super(element, role ?? 'option',
            addTabIndexWhenNonTabbable: addTabIndexWhenNonTabbable) {
    _disposer
      ..addStreamSubscription(trigger.listen(handleActivate))
      ..addFunction(() => _selectionChangeStreamSub?.cancel());
  }

  @HostBinding('class.disabled')
  @override
  bool get disabled => super.disabled;

  /// Whether the item should be hidden.
  ///
  /// False by default.
  @HostBinding('class.hidden')
  @Input()
  bool isHidden = false;

  /// The value this selection item represents.
  ///
  /// If the object implements [HasUIDisplayName], it will render use
  /// the `uiDisplayName` field as the label for the item. Otherwise, the label
  /// is only generated by this component if an [ItemRenderer] is provided
  /// (via the `itemRenderer` property).
  @Input()
  @override
  T value;

  bool _supportsMultiSelect = false;

  /// Whether the container supports selecting multiple items.
  @HostBinding('class.multiselect')
  bool get supportsMultiSelect => _supportsMultiSelect;

  /// Whether to hide the checkbox.
  ///
  /// False by default.
  @Input()
  bool hideCheckbox = false;

  /// A function to render an item as a String.
  ///
  /// It is required that this function be pure, or change its identity when
  /// internal state has changed. Otherwise the item will not know it needs to
  /// update the label. If none is provided, no label is generated (labels can
  /// still be passed as content).
  @Input()
  @override
  ItemRenderer<T> itemRenderer = nullRenderer;

  @Input()
  @override
  @Deprecated('Use factoryrenderer instead as it will produce more '
      'tree-shakeable code.')
  ComponentRenderer componentRenderer;

  /// Returns a [ComponentFactory] for dynamic component loader to use to render
  /// an item.
  ///
  /// It is required that this function be pure, or change its identity when
  /// internal state has changed. Otherwise the item will not know it needs to
  /// update the component.
  @Input()
  @override
  FactoryRenderer<RendersValue, T> factoryRenderer;

  /// If true, check marks are used instead of checkboxes to indicate whether or
  /// not the item is selected for multi-select items.
  ///
  /// This particular style is used in material menu dropdown for multi-select
  /// menu item groups.
  @Input()
  bool useCheckMarks = false;

  /// If true, triggering this item component will select the [value] within the
  /// [selection]; if false, triggering this item component will do nothing.
  @Input()
  set selectOnActivate(bool value) {
    _selectOnActivate = value;
  }

  bool _selectOnActivate = true;

  /// If true and selectOnActivate is true, triggering this item component will
  /// deselect the currently selected [value] within the [selection]; if false,
  /// triggering this component when [value] is selected will do nothing.
  @Input()
  set deselectOnActivate(bool value) {
    _deselectOnActivate = value;
  }

  bool _deselectOnActivate = true;

  bool get valueHasLabel => valueLabel != null;
  String get valueLabel {
    if (value == null) {
      return null;
    } else if (componentRenderer == null &&
        factoryRenderer == null &&
        !identical(itemRenderer, nullRenderer)) {
      return itemRenderer(value);
    }
    return null;
  }

  SelectionModel<T> _selection;
  @override
  SelectionModel<T> get selection => _selection;

  /// Selection model to update with changes.
  @Input()
  @override
  set selection(SelectionModel<T> sel) {
    _selection = sel;
    _supportsMultiSelect = sel is MultiSelectionModel<T>;

    // Eventually change this component to onpush. This should be step in that
    // direction to support onpush components that use this component. There may
    // be other mutable state that needs to trigger change detection.
    _selectionChangeStreamSub?.cancel();
    _selectionChangeStreamSub = sel.selectionChanges.listen((_) {
      _cdRef.markForCheck();
    });
  }

  /// Manually mark items selected.
  @Input()
  bool selected = false;

  /// Whether to cause dropdown to be closed on activation.
  ///
  /// True by default.
  @Input()
  bool closeOnActivate = true;

  // TODO(google): Remove after migration from ComponentRenderer is complete
  Type get componentType =>
      componentRenderer != null ? componentRenderer(value) : null;

  ComponentFactory get componentFactory =>
      factoryRenderer != null ? factoryRenderer(value) : null;

  @HostBinding('attr.aria-checked')
  bool get isAriaChecked =>
      !supportsMultiSelect || hideCheckbox ? null : isSelected;

  /// Whether this item should be marked as selected.
  @HostBinding('class.selected')
  bool get isSelected => _isMarkedSelected || _isSelectedInSelectionModel;

  bool get _isMarkedSelected => selected != null && selected;
  bool get _isSelectedInSelectionModel =>
      value != null && (_selection?.isSelected(value) ?? false);

  void handleActivate(UIEvent e) {
    var hasCheckbox = supportsMultiSelect && !hideCheckbox;
    if (_dropdown != null && closeOnActivate && !hasCheckbox) {
      _dropdown.close();
      if (e is KeyboardEvent) {
        e.stopPropagation();
      }
    }

    if (_activationHandler?.handle(e, value) ?? false) return;
    if (_selectOnActivate && _selection != null && value != null) {
      if (!_selection.isSelected(value)) {
        _selection.select(value);
      } else if (_deselectOnActivate) {
        _selection.deselect(value);
      }
    }
  }

  @visibleForTemplate
  void onLoadCustomComponent(ComponentRef ref) {}

  @override
  void ngOnDestroy() {
    _disposer.dispose();
  }
}

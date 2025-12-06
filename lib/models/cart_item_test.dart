class CartItem {
  final String name;
  String initial_product;
  int quantity;
  final double price;
  final String category_name;
  final String picture;
  final String princo;
  final String category;
  int is_variant;
  int is_sold;
  final String? variantName;
  final double? variantPrice;
  bool selected;

  CartItem({
    required this.name,
    required this.initial_product,
    required this.quantity,
    required this.price,
    required this.category_name,
    required this.picture,
    required this.princo,
    required this.category,
    this.is_variant = 0,
    this.is_sold = 0,
    this.variantName,
    this.variantPrice,
    this.selected = false,
  });

  CartItem copyWith({
    String? name,
    String? initial_product,
    int? quantity,
    double? price,
    String? category_name,
    String? image_product,
    String? printco,
    String? picture,
    String? category,
    int? is_variant,
    int? is_sold,
    String? variantName,
    double? variantPrice,
  }) {
    return CartItem(
      name: name ?? this.name,
      initial_product: initial_product ?? this.initial_product,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      category_name: category_name ?? this.category_name,
      picture: picture ?? this.picture,
      princo: printco ?? princo,
      category: category ?? this.category,
      is_variant: is_variant ?? this.is_variant,
      is_sold: is_sold ?? this.is_sold,
      variantName: variantName ?? this.variantName,
      variantPrice: variantPrice ?? this.variantPrice,
    );
  }
}

from std.reflection import reflect


struct TypeId(Equatable, ImplicitlyCopyable):
    """Identifies a type at runtime.

    Built from a hash of the type's name as the compiler reflects it, which
    includes the module for user-defined types, so two distinct types compare
    unequal.
    """

    # TODO: hash the type's full structure instead of its name: its path, its
    # generic arguments, and the package it's defined in, so two otherwise
    # identical types from different packages or scopes never share an id.
    # `reflect[T].name()` leaves standard library types unqualified
    # (`List[String]`).
    var _id: UInt64
    var _name: StaticString

    @staticmethod
    def of[T: AnyType]() -> Self:
        """Return the id of `T`."""
        var name = reflect[T].name()
        return Self(_id=hash(name), _name=name)

    def __init__(out self, *, _id: UInt64, _name: StaticString):
        self._id = _id
        self._name = _name

    def __eq__(self, other: Self) -> Bool:
        return self._id == other._id

    def name(self) -> StaticString:
        """Return the type's name, for logging."""
        return self._name

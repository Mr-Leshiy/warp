from std.reflection import reflect


struct TypeId(Equatable, ImplicitlyCopyable):
    """Identifies a type at runtime.

    Built from the type's name as the compiler reflects it, which includes
    the module for user-defined types, so two distinct types compare unequal.
    """

    # TODO: replace the name with a hash of the type's full structure: its
    # path, its generic arguments, and the package it's defined in, so two
    # otherwise identical types from different packages or scopes never share
    # an id. `reflect[T].name()` leaves standard library types unqualified
    # (`List[String]`), and comparing names costs a string comparison.
    var _name: StaticString

    @staticmethod
    def of[T: AnyType]() -> Self:
        """Return the id of `T`."""
        return Self(_name=reflect[T].name())

    def __init__(out self, *, _name: StaticString):
        self._name = _name

    def __eq__(self, other: Self) -> Bool:
        return self._name == other._name

    def name(self) -> StaticString:
        """Return the type's name, for logging."""
        return self._name

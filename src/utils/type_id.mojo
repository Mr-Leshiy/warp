from std.reflection import reflect


struct TypeId(Equatable, ImplicitlyCopyable, Writable):
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

    @staticmethod
    def of[T: AnyType]() -> Self:
        """Return the id of `T`."""
        return Self(_id=hash(reflect[T].name()))

    def __init__(out self, *, _id: UInt64):
        self._id = _id

    def __eq__(self, other: Self) -> Bool:
        return self._id == other._id

    def write_to(self, mut writer: Some[Writer]):
        writer.write("TypeId(", self._id, ")")

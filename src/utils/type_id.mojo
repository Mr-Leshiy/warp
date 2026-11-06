from std.reflection import reflect


@fieldwise_init
struct TypeId(Equatable, ImplicitlyCopyable, Writable):
    """Identifies a type at runtime.

    Built from a hash of the type's name as the compiler reflects it, which
    includes the module for user-defined types, so two distinct types compare
    unequal.
    """

    var _id: UInt64
    """Hash of the type's reflected name."""

    @staticmethod
    def of[T: AnyType]() -> Self:
        """Return the id of `T`."""
        return Self(_id=hash(reflect[T].name()))

    def write_to(self, mut writer: Some[Writer]):
        """Write the id as `TypeId(<hash>)`, for logging.

        Only the hash is kept, so the type's name can't be recovered here.
        """
        writer.write("TypeId(", self._id, ")")

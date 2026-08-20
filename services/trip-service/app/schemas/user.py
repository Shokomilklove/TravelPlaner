from marshmallow import Schema, fields, validate


class UserUpdateSchema(Schema):
    full_name = fields.String(validate=validate.Length(min=1, max=255))
    password = fields.String(validate=validate.Length(min=8, max=128))

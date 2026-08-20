from marshmallow import Schema, fields, validate


class RegisterSchema(Schema):
    email = fields.Email(required=True)
    password = fields.String(required=True, validate=validate.Length(min=8, max=128))
    full_name = fields.String(required=True, validate=validate.Length(min=1, max=255))


class LoginSchema(Schema):
    email = fields.Email(required=True)
    password = fields.String(required=True)

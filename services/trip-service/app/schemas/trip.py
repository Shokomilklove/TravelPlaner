from marshmallow import (
    Schema,
    ValidationError,
    fields,
    validate,
    validates_schema,
)

_CURRENCY = validate.Length(equal=3)
_STATUS = validate.OneOf(["draft", "planning", "planned"])


class TripCreateSchema(Schema):
    title = fields.String(validate=validate.Length(max=255))
    origin = fields.String(required=True, validate=validate.Length(min=1, max=255))
    destination = fields.String(required=True, validate=validate.Length(min=1, max=255))
    start_date = fields.Date(required=True)
    end_date = fields.Date(required=True)
    budget_amount = fields.Float(allow_none=True, validate=validate.Range(min=0))
    budget_currency = fields.String(validate=_CURRENCY)
    travelers = fields.Integer(validate=validate.Range(min=1, max=50))
    preferences = fields.Dict()

    @validates_schema
    def _validate_dates(self, data, **kwargs):
        if (
            data.get("start_date")
            and data.get("end_date")
            and data["end_date"] < data["start_date"]
        ):
            raise ValidationError(
                "end_date must be on or after start_date", field_name="end_date"
            )


class TripUpdateSchema(Schema):
    title = fields.String(validate=validate.Length(min=1, max=255))
    origin = fields.String(validate=validate.Length(min=1, max=255))
    destination = fields.String(validate=validate.Length(min=1, max=255))
    start_date = fields.Date()
    end_date = fields.Date()
    budget_amount = fields.Float(allow_none=True, validate=validate.Range(min=0))
    budget_currency = fields.String(validate=_CURRENCY)
    travelers = fields.Integer(validate=validate.Range(min=1, max=50))
    preferences = fields.Dict()
    status = fields.String(validate=_STATUS)

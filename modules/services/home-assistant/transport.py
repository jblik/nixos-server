"""Retain complete journey details for the commute dashboard."""

from opendata_transport import OpendataTransport as BaseOpendataTransport


class OpendataTransport(BaseOpendataTransport):
    @staticmethod
    def get_connection(connection):
        details = BaseOpendataTransport.get_connection(connection)
        details["raw"] = connection
        for section in connection["sections"]:
            journey = section["journey"]
            if journey is not None:
                details["category"] = journey["category"]
                details["service_number"] = journey["number"]
                break
        return details

    async def async_get_data(self):
        # The upstream dictionary retains old entries when fewer results return.
        self.connections = {}
        await super().async_get_data()

@IsTest
public class ErpCalloutMock implements HttpCalloutMock {
    private final List<Integer> statusCodes;
    private Integer calls = 0;
    public HttpRequest lastRequest;

    /** Returns the given status codes in order; the last one repeats. */
    public ErpCalloutMock(List<Integer> statusCodes) {
        this.statusCodes = statusCodes;
    }

    public HttpResponse respond(HttpRequest req) {
        lastRequest = req;
        Integer code = statusCodes[Math.min(calls, statusCodes.size() - 1)];
        calls++;
        HttpResponse res = new HttpResponse();
        res.setStatusCode(code);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(code < 300 ? '{"id":"ERP-' + calls + '"}' : '{"error":"synthetic failure"}');
        return res;
    }

    public Integer callCount() {
        return calls;
    }
}

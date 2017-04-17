import HTTP
import JSON
import Vapor
import Auth
import Foundation
import JWT
import Node
import Cookies
import Fluent
import FluentMySQL

final class ReviewController{
    let pubDrop: Droplet

    init(to drop: Droplet, cookieSetter: AuthMiddlewareJWT, protect: RedirectAuthMiddlewareJWT) {
        pubDrop = drop

        let receiver = drop.grouped("review").grouped(cookieSetter).grouped(protect)
        receiver.get(handler: receiverSummary)
        receiver.get("documents", handler: documentIndex)

        let documentreceiver = receiver.grouped("documents")

        documentreceiver.get(":id", handler: commentariesSummary)
        documentreceiver.get(":id","commentaries", handler: commentaryIndex)
        documentreceiver.get(":id","commentaries", ":commentaryId", handler: commentarySummary)
        receiver.get("commentaries", ":commentaryId","comments", handler: commentIndex)
        receiver.post("commentaries", ":commentaryId", ":command", handler: commentaryUpdate)
    }
    func documentIndex(_ request: Request)throws -> ResponseRepresentable {

        let documentsArray = try Document.query().filter("archived", .notEquals, true).all()
        let commentaryStatusCounts = try Commentary.query().filter(CommentaryConstants.status, .in, [CommentaryStatus.new, CommentaryStatus.submitted, CommentaryStatus.analysis]).all().reduce([:]) {
            ( accu, element) in
            var accu2: [String: Int] = accu as! [String : Int]
            if let stat = element.status , let docid = element.document?.uint {
                let counthash = stat + String(docid)
                accu2[counthash] = (accu2[counthash] ?? 0) + 1
            }
            return accu2
        }


        var response: [String: Node] = [:]
        var results: [Node] = []

        for document in documentsArray {
            var result: [String: Node] = document.forJSON()
            //            if let mysql = pubDrop.database?.driver as? MySQLDriver {
            //                let version = try mysql.raw("SELECT status, COUNT(status) AS occurrence FROM commentaries GROUP BY status;")
            //                let aa = version.array
            //            }
            let docid = String(describing: document.id!.uint!)
            let countSubmitted: Int = commentaryStatusCounts[CommentaryStatus.submitted + docid] as? Int ?? 0
            let countNew: Int = commentaryStatusCounts[CommentaryStatus.new + docid]  as? Int ?? 0
            let countAnalysis: Int = commentaryStatusCounts[CommentaryStatus.analysis + docid] as? Int ?? 0
            let buttonStyle = countAnalysis == 0 ? "btn-default" : "btn-primary"
            let doc = String((result[Document.JSONKeys.idbase62]?.string!)!)!
            result["newsubmit"] = Node("<p><a class=\"btn \(buttonStyle)\" href=\"/analyze/documents/\(doc)/\">Analysis <span class=\"badge\">\(countAnalysis)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-default\" href=\"/analyze/documents/\(doc)/\">Submissions <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-default\" href=\"/analyze/documents/\(doc)/\">Composition <span class=\"badge\">\(countNew)<span class=\"wb-inv\"> not submitted</span></span></a></p>")
            results.append(Node(result))

        }
        response["data"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }

    func receiverSummary(_ request: Request)throws -> ResponseRepresentable {

        var parameters = try Node(node: [
            "receive_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        return try   pubDrop.view.make("role/analyze/index", parameters)
    }

    func commentariesSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true),
            "role": Node("analyze")
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/")
        return try   pubDrop.view.make("role/analyze/commentaries", parameters)
    }
    func commentaryIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found


        let commentaryArray = try Commentary.query().filter(CommentaryConstants.documentId, documentdata!.id!).all()

        var response: [String: Node] = [:]
        var results: [Node] = []

        for commentary in commentaryArray {
            var result: [String: Node] = commentary.forJSON()
            let commentstr = String(describing: commentary.id!.int!)
            result["link"] = Node("<p><a class=\"btn btn-primary\" href=\"/analyze/documents/\(documentId)/commentaries/\(commentstr)\">View</a></p>")
            results.append(Node(result))

        }
        response["data"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }
    func commentarySummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        guard let commentaryId = request.parameters["commentaryId"]?.int, let commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        parameters["commentarieshref"] = Node("/analyze/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/")
        parameters["commentary"] = Node(commentary.forJSON())
        return try   pubDrop.view.make("role/analyze/commentary", parameters)
    }
    func commentIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let commentaryId = request.parameters["commentaryId"]?.int, let commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        guard let documentdata = try Document.find(commentary.document!) else {
            throw Abort.badRequest
        }

        //        let idInt = base62ToID(string: documentId)
        //        let documentdata = try Document.find(Node(idInt))
        //        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found


        let commentArray = try Comment.query().filter(Comment.Constants.commentaryId, commentaryId).all()

        var response: [String: Node] = [:]
        var results: [Node] = []

        for comment in commentArray {
            var result: [String: Node] = comment.forJSON()
            //            let commentstr = String(describing: commentary.id!.int!)
            //            result["link"] = Node("<p><a class=\"btn btn-primary\" href=\"/receive/documents/\(documentId)/commentaries/\(commentstr)\">View</a></p>")
            results.append(Node(result))

        }
        response["data"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }
    func commentaryUpdate(_ request: Request)throws -> ResponseRepresentable {
        guard let commentaryId = request.parameters["commentaryId"]?.int, var commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        guard let documentdata = try Document.find(commentary.document!) else {
            throw Abort.badRequest
        }
        if let commentator = request.data["commentary"]?.object {
            if let item = commentator["status"]?.string {
                let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)

                if !(newitem == commentary.status) {
                    commentary.updateStatus(to: newitem)
                    try commentary.save()
                }
            }
        }

        var response: [String: Node] = [:]

        response["commentary"] = Node(commentary.forJSON())
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }
    
    
}
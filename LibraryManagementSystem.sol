// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";


// Custom Erros

error libraryManagementSystem__OnlyMasterCanDoThis();
error libraryManagementSystem__OnlyLibrariansCanDoThis(); 
error libraryManagementSystem__OnlyMembershipHolderCanDoThis(); 
error libraryManagementSystem__ThisBookIdDoesNotExist(); 
error libraryManagementSystem__OnlyExecutivesCanCallThis();

contract libraryManagementSystem is ERC20("Magnus Mage Token","MMT")  {

    ///////////////////
    ///// structs/////
    //////////////////

    struct Book {
        uint id;
        bytes title;
        bytes author;
        bytes subject;
        bytes category;
        uint bookCopies;
        uint publicationDate;
        bool available;
        uint rackId;
    }

    struct Rack {
        uint rackId;
        bytes location;
        Book[] books;
    }

    struct Member {
        uint id;
        address memberAddress;
        uint borrowedBooks;
        uint returnedBooks;
        uint reservation;
        bool active;
    }

    
    /////////////////////
    //// State Variables
    /////////////////////

    uint public constant LATE_RETURN_FINE = 20;
    uint public constant BORROW_DEADLINE = 2 minutes;
    uint public constant BORROW_LIMIT = 5;
    uint public constant MEMBERSHIP_FEE = 10;
    address public immutable MASTER_LIBRARIAN;

    uint public bookId;
    uint public memberId;

    Member[]  totalMembers;
    address[]  librarians;
    Book[]  totalBooks;
     

    mapping(uint RackId => Rack)  idToRack;
    mapping(uint BookId => Book)  idToBooks;
    mapping(address => bool)  isLibrarian;
    mapping(uint bookId => mapping( uint MemberId => bool)) isReserved;
    mapping(address Borrower => mapping(uint BookId => bool )) bookBorrowed;
    mapping(uint BookId => bool)  bookExist;
    mapping(uint BookId => uint[])  bookReservations;
    mapping(address MemberAddress =>mapping(uint BookId => uint))  addressToBorrowtime;
    mapping(uint BookId =>  uint[] MemberIds)  borrowedBy; 
    mapping(address MemberAddress => Member)  addressToMembers;

    mapping(bytes => Book[])  titleToBooks;
    mapping(bytes => Book[])  authorToBooks;
    mapping(bytes => Book[])  subjectToBooks;
    mapping(bytes => Book[])  categoryToBooks;
    mapping(uint => Book[])  publicationDateToBooks;


    ////////////////
    //// Events////
    ///////////////

    event BooksAdded(
        address indexed librarian,
        uint indexed id,
        uint indexed copies
    );

    event BooksUpdated(
        address indexed librarian,
        uint indexed id,
        uint indexed copies
    );

    event BooksDeleted(
        address indexed librarian,
        uint indexed id
    );

    event BookReserved(
        address indexed user,
        uint indexed id
    );

    event BookReservedRemoved(
        address indexed user,
        uint indexed id
    );

    event bookBorrow(
        uint indexed bookId,
        uint indexed memberId,
        uint indexed timeStamp
    );

    event bookReturned(
        uint indexed bookId,
        uint indexed memberId,
        uint indexed timeStamp
    );

    event gotBook(
        uint indexed bookId,
        uint indexed memberId,
        uint indexed timeStampe
    );

    event LibrarianAdded(
        address indexed librarian
    );

    event MemberShip(
        uint indexed memberId,
        address indexed memberAddres
    );

    //////////////////
    //////modifiers//
    /////////////////

    modifier onlyMaster(){
        if(msg.sender != MASTER_LIBRARIAN){
            revert libraryManagementSystem__OnlyMasterCanDoThis(); 
        }
        _;
    }

    modifier onlyLibrarian(){
        if(isLibrarian[msg.sender] || msg.sender == MASTER_LIBRARIAN){
           _;
        }else{
            revert libraryManagementSystem__OnlyLibrariansCanDoThis(); 
        }
        
    }

    modifier onlyMember(){
        if(!addressToMembers[msg.sender].active){
            revert libraryManagementSystem__OnlyMembershipHolderCanDoThis();
        }
        _;
    }

    modifier onlyExective(){
        if(addressToMembers[msg.sender].active || isLibrarian[msg.sender] || msg.sender == MASTER_LIBRARIAN ){
            _;
        }else{
            revert libraryManagementSystem__OnlyExecutivesCanCallThis();
        }
    }
    modifier isBookExist(uint _bookId){
        if(!bookExist[_bookId]){
            revert  libraryManagementSystem__ThisBookIdDoesNotExist(); 
        }
        _;
    }
    
    //////////////////
    /// constructor
    /////////////////

    constructor() {
        MASTER_LIBRARIAN = msg.sender;
    }

    // function for addng book in the library
    function addBooks(
        bytes memory _title,
        bytes memory _author,
        bytes memory _subjects,
        bytes memory _category,
        bytes memory _location,
        uint _publicationDate,
        uint _bookCopies,
        uint _rackId
    )   external 
        onlyLibrarian
    {

        Book storage book = idToBooks[bookId];
        book.id = bookId;
        book.title = _title;
        book.author = _author;  
        book.subject = _subjects;  
        book.category = _category;
        book.publicationDate = _publicationDate;
        book.bookCopies = _bookCopies;  
        book.available = true;  
        book.rackId = _rackId;
        idToRack[_rackId].rackId = _rackId;
        idToRack[_rackId].location = _location;
        idToRack[_rackId].books.push(book);
        totalBooks.push(book);
        bookExist[bookId] = true;
        titleToBooks[_title].push(book);
        categoryToBooks[_category].push(book);
        subjectToBooks[_subjects].push(book);
        authorToBooks[_author].push(book);
        publicationDateToBooks[_publicationDate].push(book);
        emit BooksAdded(msg.sender, bookId, _bookCopies); 
        bookId++;   

    }

    // for updating the books
    function updateBook(uint _bookId, uint _bookCopies) external onlyLibrarian isBookExist(_bookId) {
        Book storage book = idToBooks[_bookId];
        book.bookCopies = _bookCopies;
        book.available = true;
        emit BooksUpdated(msg.sender, _bookId, _bookCopies);
    }


    // for deleting the books
    function deleteBook(uint _bookId) external onlyLibrarian isBookExist(_bookId){
        idToBooks[_bookId].available = false;
        emit BooksDeleted(msg.sender, _bookId);
    }


    // for borrowing the book
    function borrow(uint _bookId) external onlyMember isBookExist(_bookId) {
        require(!bookBorrowed[msg.sender][_bookId], "You Already Borrowed This Book");
        require(addressToMembers[msg.sender].borrowedBooks < BORROW_LIMIT, "You Cannot Borrow More");
        require(idToBooks[_bookId].available , "Book Is Not Available");
        idToBooks[_bookId].bookCopies--;
        if(idToBooks[_bookId].bookCopies == 0){
            idToBooks[_bookId].available = false;
        }
        addressToMembers[msg.sender].borrowedBooks++;
        borrowedBy[_bookId].push(addressToMembers[msg.sender].id);
        addressToBorrowtime[msg.sender][_bookId] = block.timestamp;
        bookBorrowed[msg.sender][_bookId] = true;
        emit bookBorrow(_bookId, addressToMembers[msg.sender].id , block.timestamp);
    }


    // returning the borrowed book
    function returnBook(uint _bookId) external onlyMember isBookExist(_bookId) {
        require(bookBorrowed[msg.sender][_bookId], "You Cannot Return a Book You Haven't Borrowed");

        if (block.timestamp >= addressToBorrowtime[msg.sender][_bookId] + BORROW_DEADLINE) {
            require(balanceOf(msg.sender) >= LATE_RETURN_FINE, "Insufficient Tokens for Paying Late Return Fine");
            transfer(address(this), LATE_RETURN_FINE);
        }

        idToBooks[_bookId].bookCopies++;
        addressToMembers[msg.sender].borrowedBooks--;
        addressToMembers[msg.sender].returnedBooks++;
        bookBorrowed[msg.sender][_bookId] = false;

        if (bookReservations[_bookId].length > 0) {
            uint reservedMember = bookReservations[_bookId][0];
            for (uint i = 0; i < bookReservations[_bookId].length - 1; i++) {
                bookReservations[_bookId][i] = bookReservations[_bookId][i + 1];
            }
            bookReservations[_bookId].pop();
            
            if(idToBooks[_bookId].bookCopies > 0){
                address reservedMemberAddress = totalMembers[reservedMember].memberAddress;
                addressToMembers[reservedMemberAddress].borrowedBooks++;
                bookBorrowed[reservedMemberAddress][_bookId] = true;
                addressToMembers[reservedMemberAddress].reservation--;
                borrowedBy[_bookId].push(reservedMember);
                addressToBorrowtime[reservedMemberAddress][_bookId] = block.timestamp;
                idToBooks[_bookId].bookCopies--;
                emit gotBook(_bookId, addressToMembers[reservedMemberAddress].id, block.timestamp);
            }
            
        }

        if(idToBooks[_bookId].bookCopies > 0){
            idToBooks[_bookId].available = true;
        }else{
            idToBooks[_bookId].available = false;
        }
        isReserved[_bookId][addressToMembers[msg.sender].id] = false;
        emit bookReturned(_bookId, addressToMembers[msg.sender].id, block.timestamp);
        
    }

    //function for Reserve The book in advance while availabe
    function reserveBook(uint _bookId) external onlyMember isBookExist(_bookId) {
        require(!bookBorrowed[msg.sender][_bookId], "You Cannot Reserve a Book You Have Borrowed");
        require(!idToBooks[_bookId].available, "Book Is Available You Can Borrow");
        require(!isReserved[_bookId][addressToMembers[msg.sender].id], "You Already Reserved This Book");
        bookReservations[_bookId].push(addressToMembers[msg.sender].id);
        addressToMembers[msg.sender].reservation++;
        isReserved[_bookId][addressToMembers[msg.sender].id] = true;
        emit BookReserved(msg.sender, addressToMembers[msg.sender].id);
    }

    // function for removing the reservation
    function removeReservation(uint _bookId) external onlyMember isBookExist(_bookId) {
        require(addressToMembers[msg.sender].reservation > 0, "You Don't Have Any Reservation");
        uint memberID = addressToMembers[msg.sender].id;
        bool found = removeElement(bookReservations[_bookId], memberID);
        require(found, "You Don't Have a Reservation for This Book");
        addressToMembers[msg.sender].reservation--;
        emit BookReservedRemoved(msg.sender,addressToMembers[msg.sender].id);
    }

    // helper function
    function removeElement(uint[] storage arr, uint value) internal returns (bool) {
        for (uint i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                for (uint j = i; j < arr.length - 1; j++) {
                    arr[j] = arr[j + 1];
                }
                arr.pop();
                return true;
            }
        }
        return false;
    }

    // mint token
    function mintToken(uint amount) external {
        Member storage member = addressToMembers[msg.sender];
        require(member.memberAddress != address(0), "Go Register First");
        _mint(msg.sender, amount);
    }

    // function for library registration
    function register() external {
        Member storage member = addressToMembers[msg.sender];
        require(member.memberAddress == address(0), "Already Registered");
        member.id = memberId;
        member.memberAddress = msg.sender;
        totalMembers.push(member);
        memberId++;
    }

    // function for buying membership
    function buyMembership() external {
        Member storage member = addressToMembers[msg.sender];
        require(member.memberAddress != address(0), "Go Register First");
        require(!addressToMembers[msg.sender].active, "Already Active Membership");
        require(balanceOf(msg.sender) >= MEMBERSHIP_FEE , "InSuffcient Token To Get The Membership");
        transfer(address(this), MEMBERSHIP_FEE);
        member.active = true;
        emit MemberShip(member.id, msg.sender);
    }

    // function to add librarian
    function addLibrarian(address _user) external onlyMaster {
        require(_user != address(0), "You Cannot Include Address Zero");
        require(!isLibrarian[_user], "User Already Librarian");
        librarians.push(_user);
        isLibrarian[_user] = true;
        emit LibrarianAdded(_user);
    }

    //function to remove librarian
    function removeLibrariran(address _user) external onlyMaster {
        require(_user != address(0), "Address Zero Not Allowed");
        require(isLibrarian[_user], "User Is Not Librarian");
        for (uint256 i = 0; i < librarians.length; i++) {
            if (librarians[i] == _user) {
                address temp = librarians[i];
                librarians[i] = librarians[librarians.length - 1];
                librarians[librarians.length - 1] = temp;
                break;
            }
        }

        librarians.pop();
        isLibrarian[_user] = false;
    }


    //////////////////
    /// view functions
    //////////////////


    function getBookBorrowers(uint _bookId) public  onlyExective isBookExist(_bookId)  view returns(uint[] memory) {
        return borrowedBy[_bookId];
    }

    function getAllBooks() public onlyExective view returns(Book[] memory){
        return totalBooks;
    }

    function getBorrowedBooks() public view onlyMember returns(uint){
        return addressToMembers[msg.sender].borrowedBooks;
    }
    function getReturnBooks() public view onlyMember returns(uint){
        return addressToMembers[msg.sender].returnedBooks;
    }
    function getReservedBooks() public view onlyMember returns(uint){
        return addressToMembers[msg.sender].reservation;
    }

    function SearchByTitle(bytes memory _title) public onlyExective view returns(Book[] memory){
        require(titleToBooks[_title].length > 0, "No books found with this title");
        return titleToBooks[_title];
    }

    function SearchBySubject(bytes memory _subject) public onlyExective view returns(Book[] memory){
        require(subjectToBooks[_subject].length > 0, "No books found with this subject");
        return subjectToBooks[_subject];
    }

    function SearchByCategory(bytes memory _category) public onlyExective view returns(Book[] memory){
        require(categoryToBooks[_category].length > 0, "No books found in this category");
        return categoryToBooks[_category];
    }

    function SearchByAuthor(bytes memory _author) public onlyExective view returns(Book[] memory){
        require(authorToBooks[_author].length > 0, "No books found by this author");
        return authorToBooks[_author];
    }

    function SearchByPublicationDate(uint  _date) public onlyExective view returns(Book[] memory){
        require(publicationDateToBooks[_date].length > 0, "No books found with this publication date");
        return publicationDateToBooks[_date];
    }

    function getBookReservation(uint _bookId) public onlyExective isBookExist(_bookId) view returns(uint[] memory){
        return bookReservations[_bookId];
    }

    function getBookLocation(uint _bookId) public onlyExective isBookExist(_bookId) view returns(uint RackNumber,bytes memory Location){
        RackNumber = idToBooks[_bookId].rackId;
        Location = idToRack[idToBooks[_bookId].rackId].location;
    }

    function getAllMember() public onlyExective view returns(Member[] memory){
        return totalMembers;
    }

    function getBookInfo(uint _bookId) onlyMember public onlyExective view returns(Book memory){
        return idToBooks[_bookId];
    } 

    function getCheckedOutBooksById(uint _memberId) public onlyExective view returns(uint[] memory) {
        address memberAddress = totalMembers[_memberId].memberAddress;
        uint[] memory checkedOutBooks = new uint[](addressToMembers[memberAddress].borrowedBooks);
        uint count = 0;
        for (uint i = 0; i < totalBooks.length; i++) {
            if (bookBorrowed[memberAddress][totalBooks[i].id]) {
                checkedOutBooks[count] = totalBooks[i].id;
                count++;
            }
        }
        return checkedOutBooks;
    }


   

 
}





